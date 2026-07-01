#import "EmbeddedLlamaBridge.h"

#include "llama.h"
#include "mtmd-helper.h"
#include "mtmd.h"

#include <CoreGraphics/CoreGraphics.h>
#include <atomic>
#include <vector>

static NSString * const EmbeddedLlamaErrorDomain = @"com.smol.smolpad.embedded-llama";

static void llama_batch_clear_tokens(struct llama_batch & batch) {
    batch.n_tokens = 0;
}

static void llama_batch_add_token(struct llama_batch & batch, llama_token token, llama_pos pos, bool logits) {
    const int index = static_cast<int>(batch.n_tokens);
    batch.token[index] = token;
    batch.pos[index] = pos;
    batch.n_seq_id[index] = 1;
    batch.seq_id[index][0] = 0;
    batch.logits[index] = logits ? 1 : 0;
    batch.n_tokens += 1;
}

static bool embedded_abort_callback(void * data) {
    auto * cancelled = static_cast<std::atomic<bool> *>(data);
    return cancelled != nullptr && cancelled->load();
}

static NSError * EmbeddedLlamaMakeError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:EmbeddedLlamaErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString * _Nullable drain_utf8(std::vector<char> & pending, const char * bytes, size_t count) {
    if (bytes != nullptr && count > 0) {
        pending.insert(pending.end(), bytes, bytes + count);
    }

    if (pending.empty()) {
        return nil;
    }

    pending.push_back('\0');
    NSString * decoded = [[NSString alloc] initWithCString:pending.data() encoding:NSUTF8StringEncoding];
    pending.pop_back();

    if (decoded != nil) {
        pending.clear();
        return decoded;
    }

    return nil;
}

static NSString * format_fallback_prompt(NSString * systemPrompt,
                                         NSArray<NSDictionary<NSString *, NSString *> *> * history,
                                         NSString * userPrompt,
                                         bool hasImage) {
    NSMutableString * prompt = [NSMutableString string];
    if (systemPrompt.length > 0) {
        [prompt appendFormat:@"System:\n%@\n\n", systemPrompt];
    }

    for (NSDictionary<NSString *, NSString *> * message in history) {
        NSString * role = message[@"role"] ?: @"user";
        NSString * content = message[@"content"] ?: @"";
        if (content.length == 0) {
            continue;
        }

        [prompt appendFormat:@"%@:\n%@\n\n", role.capitalizedString, content];
    }

    if (hasImage) {
        [prompt appendString:@"User:\n<__media__>\n"];
    } else {
        [prompt appendString:@"User:\n"];
    }
    [prompt appendString:userPrompt];
    [prompt appendString:@"\n\nAssistant:\n"];
    return prompt;
}

static NSString * _Nullable apply_chat_template(struct llama_model * model,
                                                NSString * systemPrompt,
                                                NSArray<NSDictionary<NSString *, NSString *> *> * history,
                                                NSString * userPrompt,
                                                bool hasImage) {
    const char * tmpl = llama_model_chat_template(model, nullptr);
    if (tmpl == nullptr) {
        return nil;
    }

    NSMutableArray<NSDictionary<NSString *, NSString *> *> * messages = [NSMutableArray array];
    if (systemPrompt.length > 0) {
        [messages addObject:@{@"role": @"system", @"content": systemPrompt}];
    }
    [messages addObjectsFromArray:history];

    NSString * finalUserPrompt = hasImage
        ? [NSString stringWithFormat:@"%s\n%@", mtmd_default_marker(), userPrompt]
        : userPrompt;
    [messages addObject:@{@"role": @"user", @"content": finalUserPrompt}];

    std::vector<llama_chat_message> chat;
    std::vector<std::string> roles;
    std::vector<std::string> contents;
    chat.reserve(messages.count);
    roles.reserve(messages.count);
    contents.reserve(messages.count);

    for (NSDictionary<NSString *, NSString *> * message in messages) {
        NSString * role = message[@"role"] ?: @"user";
        NSString * content = message[@"content"] ?: @"";

        roles.emplace_back(role.UTF8String ?: "user");
        contents.emplace_back(content.UTF8String ?: "");
        chat.push_back(llama_chat_message {
            roles.back().c_str(),
            contents.back().c_str()
        });
    }

    const int32_t needed = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, nullptr, 0);
    if (needed <= 0) {
        return nil;
    }

    std::vector<char> buffer(static_cast<size_t>(needed) + 1, '\0');
    const int32_t written = llama_chat_apply_template(tmpl, chat.data(), chat.size(), true, buffer.data(), static_cast<int32_t>(buffer.size()));
    if (written <= 0) {
        return nil;
    }

    return [[NSString alloc] initWithBytes:buffer.data() length:static_cast<NSUInteger>(written) encoding:NSUTF8StringEncoding];
}

static NSData * _Nullable copy_rgb_bytes_from_image(UIImage * image, uint32_t * widthOut, uint32_t * heightOut) {
    CGImageRef cgImage = image.CGImage;
    if (cgImage == nil) {
        return nil;
    }

    const size_t width = CGImageGetWidth(cgImage);
    const size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) {
        return nil;
    }

    const size_t bytesPerPixel = 4;
    const size_t bytesPerRow = width * bytesPerPixel;
    NSMutableData * rgbaData = [NSMutableData dataWithLength:height * bytesPerRow];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgbaData.mutableBytes,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);

    if (context == nil) {
        return nil;
    }

    CGContextSetFillColorWithColor(context, UIColor.whiteColor.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    NSMutableData * rgbData = [NSMutableData dataWithLength:width * height * 3];
    const uint8_t * rgba = static_cast<const uint8_t *>(rgbaData.bytes);
    uint8_t * rgb = static_cast<uint8_t *>(rgbData.mutableBytes);

    for (size_t index = 0; index < width * height; index += 1) {
        rgb[index * 3 + 0] = rgba[index * 4 + 0];
        rgb[index * 3 + 1] = rgba[index * 4 + 1];
        rgb[index * 3 + 2] = rgba[index * 4 + 2];
    }

    if (widthOut != nullptr) {
        *widthOut = static_cast<uint32_t>(width);
    }
    if (heightOut != nullptr) {
        *heightOut = static_cast<uint32_t>(height);
    }

    return rgbData;
}

@implementation EmbeddedLlamaGenerationRequest

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemPrompt = @"";
        _history = @[];
        _userPrompt = @"";
        _maxTokens = 384;
    }
    return self;
}

@end

@interface EmbeddedLlamaBridge () {
    NSString * _modelPath;
    NSString * _mmprojPath;
    NSString * _modelIdentifier;
    std::atomic<bool> _cancelled;
    struct llama_model * _model;
    struct llama_context * _context;
    const struct llama_vocab * _vocab;
    struct mtmd_context * _mtmd;
    struct llama_sampler * _sampler;
    struct llama_batch _batch;
    bool _batchInitialized;
    int32_t _nBatch;
}
@end

@implementation EmbeddedLlamaBridge

- (instancetype)initWithModelPath:(NSString *)modelPath
                       mmprojPath:(NSString *)mmprojPath
                  modelIdentifier:(NSString *)modelIdentifier {
    self = [super init];
    if (self) {
        _modelPath = [modelPath copy];
        _mmprojPath = [mmprojPath copy];
        _modelIdentifier = [modelIdentifier copy];
        _cancelled.store(false);
        _model = nullptr;
        _context = nullptr;
        _vocab = nullptr;
        _mtmd = nullptr;
        _sampler = nullptr;
        _batchInitialized = false;
        _nBatch = 512;
    }
    return self;
}

- (void)dealloc {
    if (_sampler != nullptr) {
        llama_sampler_free(_sampler);
    }
    if (_batchInitialized) {
        llama_batch_free(_batch);
    }
    if (_mtmd != nullptr) {
        mtmd_free(_mtmd);
    }
    if (_context != nullptr) {
        llama_free(_context);
    }
    if (_model != nullptr) {
        llama_model_free(_model);
    }
}

- (BOOL)prepare:(NSError * _Nullable __autoreleasing *)error {
    if (_model != nullptr && _context != nullptr && _mtmd != nullptr && _sampler != nullptr) {
        return YES;
    }

    _cancelled.store(false);
    llama_backend_init();

    struct llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = -1;
    modelParams.use_mmap = true;
    modelParams.use_mlock = false;
    modelParams.check_tensors = false;

    _model = llama_model_load_from_file(_modelPath.fileSystemRepresentation, modelParams);
    if (_model == nullptr) {
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1001, [NSString stringWithFormat:@"Failed to load llama.cpp model at %@", _modelPath]);
        }
        return NO;
    }

    struct llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = 4096;
    contextParams.n_batch = 1024;
    contextParams.n_ubatch = 512;
    contextParams.n_threads = MAX(2, (int32_t)MIN((NSInteger)8, NSProcessInfo.processInfo.activeProcessorCount));
    contextParams.n_threads_batch = contextParams.n_threads;
    contextParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    contextParams.offload_kqv = true;
    contextParams.op_offload = true;
    contextParams.abort_callback = embedded_abort_callback;
    contextParams.abort_callback_data = &_cancelled;

    _context = llama_init_from_model(_model, contextParams);
    if (_context == nullptr) {
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1002, @"Failed to create the llama.cpp context.");
        }
        return NO;
    }

    _vocab = llama_model_get_vocab(_model);
    _nBatch = static_cast<int32_t>(MAX(256u, MIN(1024u, llama_n_ctx(_context) / 2)));

    struct mtmd_context_params mtmdParams = mtmd_context_params_default();
    mtmdParams.use_gpu = true;
    mtmdParams.n_threads = contextParams.n_threads;
    mtmdParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    mtmdParams.warmup = true;
    mtmdParams.batch_max_tokens = _nBatch;
    mtmdParams.cb_eval = contextParams.cb_eval;
    mtmdParams.cb_eval_user_data = contextParams.cb_eval_user_data;

    _mtmd = mtmd_init_from_file(_mmprojPath.fileSystemRepresentation, _model, mtmdParams);
    if (_mtmd == nullptr) {
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1003, [NSString stringWithFormat:@"Failed to load the multimodal projector at %@", _mmprojPath]);
        }
        return NO;
    }

    struct llama_sampler_chain_params samplerParams = llama_sampler_chain_default_params();
    _sampler = llama_sampler_chain_init(samplerParams);
    llama_sampler_chain_add(_sampler, llama_sampler_init_greedy());

    _batch = llama_batch_init(_nBatch, 0, 1);
    _batchInitialized = true;
    return YES;
}

- (BOOL)generate:(EmbeddedLlamaGenerationRequest *)request
         onChunk:(EmbeddedLlamaChunkHandler)onChunk
           error:(NSError * _Nullable __autoreleasing *)error {
    NSError * prepareError = nil;
    if (![self prepare:&prepareError]) {
        if (error != nullptr) {
            *error = prepareError;
        }
        return NO;
    }

    _cancelled.store(false);
    llama_sampler_reset(_sampler);
    llama_memory_clear(llama_get_memory(_context), true);

    NSString * formattedPrompt = apply_chat_template(
        _model,
        request.systemPrompt ?: @"",
        request.history ?: @[],
        request.userPrompt ?: @"",
        request.image != nil
    );
    if (formattedPrompt == nil) {
        formattedPrompt = format_fallback_prompt(
            request.systemPrompt ?: @"",
            request.history ?: @[],
            request.userPrompt ?: @"",
            request.image != nil
        );
    }

    struct mtmd_input_text inputText;
    inputText.text = formattedPrompt.UTF8String;
    inputText.add_special = true;
    inputText.parse_special = true;

    mtmd_bitmap * bitmap = nullptr;
    NSData * rgbData = nil;
    const mtmd_bitmap * bitmaps[1] = { nullptr };
    size_t bitmapCount = 0;

    if (request.image != nil) {
        uint32_t width = 0;
        uint32_t height = 0;
        rgbData = copy_rgb_bytes_from_image(request.image, &width, &height);
        if (rgbData == nil) {
            if (error != nullptr) {
                *error = EmbeddedLlamaMakeError(1004, @"Failed to convert the selected note into RGB image data.");
            }
            return NO;
        }

        bitmap = mtmd_bitmap_init(width, height, static_cast<const unsigned char *>(rgbData.bytes));
        if (bitmap == nullptr) {
            if (error != nullptr) {
                *error = EmbeddedLlamaMakeError(1005, @"Failed to initialize the multimodal bitmap.");
            }
            return NO;
        }
        bitmaps[0] = bitmap;
        bitmapCount = 1;
    }

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    const int32_t tokenizationResult = mtmd_tokenize(_mtmd, chunks, &inputText, bitmaps, bitmapCount);
    if (bitmap != nullptr) {
        mtmd_bitmap_free(bitmap);
    }
    if (tokenizationResult != 0) {
        mtmd_input_chunks_free(chunks);
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1006, [NSString stringWithFormat:@"Failed to tokenize the multimodal prompt (code %d).", tokenizationResult]);
        }
        return NO;
    }

    llama_pos nPast = 0;
    const int32_t evalResult = mtmd_helper_eval_chunks(_mtmd, _context, chunks, 0, 0, _nBatch, true, &nPast);
    mtmd_input_chunks_free(chunks);
    if (evalResult != 0) {
        if (_cancelled.load()) {
            if (error != nullptr) {
                *error = EmbeddedLlamaMakeError(1099, @"Generation was cancelled.");
            }
            return NO;
        }
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1007, [NSString stringWithFormat:@"Failed to evaluate the multimodal prompt (code %d).", evalResult]);
        }
        return NO;
    }

    std::vector<char> pendingUtf8;
    bool producedText = false;
    const NSInteger maxTokens = MAX((NSInteger)1, request.maxTokens);

    for (NSInteger index = 0; index < maxTokens; index += 1) {
        if (_cancelled.load()) {
            if (error != nullptr) {
                *error = EmbeddedLlamaMakeError(1099, @"Generation was cancelled.");
            }
            return NO;
        }

        const llama_token token = llama_sampler_sample(_sampler, _context, -1);
        llama_sampler_accept(_sampler, token);

        if (llama_vocab_is_eog(_vocab, token)) {
            break;
        }

        char pieceBuffer[256];
        const int32_t pieceLength = llama_token_to_piece(_vocab, token, pieceBuffer, sizeof(pieceBuffer), 0, true);
        if (pieceLength > 0) {
            NSString * decoded = drain_utf8(pendingUtf8, pieceBuffer, static_cast<size_t>(pieceLength));
            if (decoded.length > 0) {
                producedText = true;
                onChunk(decoded, NO);
            }
        }

        llama_batch_clear_tokens(_batch);
        llama_batch_add_token(_batch, token, nPast, true);
        nPast += 1;

        const int32_t decodeResult = llama_decode(_context, _batch);
        if (decodeResult != 0) {
            if (error != nullptr) {
                *error = EmbeddedLlamaMakeError(1008, [NSString stringWithFormat:@"llama_decode failed during generation (code %d).", decodeResult]);
            }
            return NO;
        }
    }

    NSString * tail = drain_utf8(pendingUtf8, nullptr, 0);
    if (tail.length > 0) {
        producedText = true;
        onChunk(tail, NO);
    }

    if (!producedText) {
        if (error != nullptr) {
            *error = EmbeddedLlamaMakeError(1009, @"The embedded vision model returned an empty response.");
        }
        return NO;
    }

    return YES;
}

- (void)cancel {
    _cancelled.store(true);
}

@end
