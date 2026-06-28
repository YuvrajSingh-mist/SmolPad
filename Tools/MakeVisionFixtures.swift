import AppKit

let outputDir = URL(fileURLWithPath: "/tmp/smolpad-vision-fixtures", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// MARK: - Messy handwriting fonts available on macOS
func handwritingFont(size: CGFloat) -> NSFont {
    for name in ["Marker Felt", "Noteworthy", "Chalkboard SE", "Bradley Hand"] {
        if let f = NSFont(name: name, size: size) { return f }
    }
    return NSFont.systemFont(ofSize: size)
}

// MARK: - Fixture model
struct Fixture {
    let name: String
    let problem: String
    let subText: String
    let category: String
    let expected: String
}

let fixtures: [Fixture] = [
    // ── Calculus ──
    Fixture(name: "calc_derivative_poly",
            problem: "d/dx [ 3x^4 - 7x^3 + 2x - 9 ]",
            subText: "Find the derivative.",
            category: "Calculus",
            expected: "12x^3 - 21x^2 + 2"),

    Fixture(name: "calc_derivative_chain",
            problem: "d/dx [ sin( x^2 + 3x ) ]",
            subText: "Use the chain rule.",
            category: "Calculus",
            expected: "(2x + 3) cos(x^2 + 3x)"),

    Fixture(name: "calc_integral",
            problem: "integral from 0 to 2 of (4x^3 - 2x + 1) dx",
            subText: "Evaluate the definite integral.",
            category: "Calculus",
            expected: "14"),

    Fixture(name: "calc_limit",
            problem: "lim x->0  sin(3x) / x",
            subText: "Evaluate the limit.",
            category: "Calculus",
            expected: "3"),

    Fixture(name: "calc_partial",
            problem: "d/dx [ x^2 y + y^3 - sin(xy) ]",
            subText: "Find the partial derivative w.r.t x.",
            category: "Calculus",
            expected: "2xy - y cos(xy)"),

    Fixture(name: "calc_gradient",
            problem: "Gradient of f = ?  where f(x,y) = x^3 + y^2 - 4xy",
            subText: "Compute the gradient vector.",
            category: "Calculus",
            expected: "(3x^2 - 4y, 2y - 4x)"),

    // ── Probability ──
    Fixture(name: "prob_expectation",
            problem: "E[X] = ?  X in {0,1,2}: p(0)=0.3, p(1)=0.5, p(2)=0.2",
            subText: "Compute the expected value.",
            category: "Probability",
            expected: "0.9"),

    Fixture(name: "prob_variance",
            problem: "Var(X) = ?  given E[X]=5, E[X^2]=34",
            subText: "Compute the variance.",
            category: "Probability",
            expected: "9"),

    Fixture(name: "prob_bayes",
            problem: "P(A|B) = ?  P(A)=0.01, P(B|A)=0.95, P(B)=0.02",
            subText: "Apply Bayes theorem.",
            category: "Probability",
            expected: "0.475"),

    // ── Linear Algebra ──
    Fixture(name: "linalg_eigenvalues",
            problem: "A = [3 1; 0 2]   find eigenvalues.",
            subText: "Solve det(A - lambda I) = 0.",
            category: "Linear Algebra",
            expected: "lambda = 3, 2"),

    Fixture(name: "linalg_dot",
            problem: "v dot w = ?   v=(1,2,3)  w=(4,-1,2)",
            subText: "Compute the dot product.",
            category: "Linear Algebra",
            expected: "8"),

    Fixture(name: "linalg_det",
            problem: "det of [2 1 3; 0 -1 4; 1 0 2] = ?",
            subText: "Compute the determinant.",
            category: "Linear Algebra",
            expected: "-2"),

    // ── ML / Deep Learning ──
    Fixture(name: "ml_mse_gradient",
            problem: "L(w) = (1/n) sum (y_i - w x_i)^2.  Find dL/dw.",
            subText: "MSE loss gradient w.r.t weight w.",
            category: "ML",
            expected: "-(2/n) sum x_i (y_i - w x_i)"),

    Fixture(name: "ml_softmax",
            problem: "softmax(z) for z = [2, 1, 0]",
            subText: "Compute softmax probabilities.",
            category: "ML",
            expected: "[0.67, 0.24, 0.09]"),

    Fixture(name: "ml_cross_entropy",
            problem: "L = -sum y_i log(yhat_i)  y=[1,0,0]  yhat=[0.7,0.2,0.1]",
            subText: "Compute cross-entropy loss.",
            category: "ML",
            expected: "0.357"),

    // ── Reinforcement Learning ──
    Fixture(name: "rl_bellman",
            problem: "V(s) = max_a [ R(s,a) + gamma V(s') ]  gamma=0.9",
            subText: "s=0: a1 R=5 s'=1 V(1)=10; a2 R=2 s'=2 V(2)=8. Find V(0).",
            category: "RL",
            expected: "14"),

    Fixture(name: "rl_qlearning",
            problem: "Q(s,a) <- Q(s,a) + alpha [ r + gamma max Q - Q(s,a) ]",
            subText: "alpha=0.1 gamma=0.9 Q=5 r=10 max Q=8. Update Q.",
            category: "RL",
            expected: "6.22"),

    Fixture(name: "rl_policy_gradient",
            problem: "Policy gradient: E[ grad log pi(a|s) * R ]",
            subText: "pi(left)=0.7 pi(right)=0.3 R=+10 for left. Compute gradient for left.",
            category: "RL",
            expected: "3.0"),
]

// MARK: - Render
for fixture in fixtures {
    for (suffix, maxDim, titleSize, detailSize, topY, bottomY) in [
        ("",      900, CGFloat(42), CGFloat(28), CGFloat(280), CGFloat(180)),
        ("-256",  256, CGFloat(18), CGFloat(14), CGFloat(100), CGFloat(60)),
        ("-512",  512, CGFloat(28), CGFloat(20), CGFloat(180), CGFloat(110)),
    ] as [(String, Int, CGFloat, CGFloat, CGFloat, CGFloat)] {
        let width = maxDim
        let height = Int(CGFloat(maxDim) * 520.0 / 900.0)
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        // Paper
        NSColor(calibratedRed: 0.969, green: 0.965, blue: 0.957, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        // Rule lines
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.47, alpha: 0.10).setStroke()
        let rule = NSBezierPath()
        var y: CGFloat = 40
        let ls = CGFloat(maxDim) * 58.0 / 900.0
        while y < size.height { rule.move(to: NSPoint(x: 20, y: y)); rule.line(to: NSPoint(x: size.width - 20, y: y)); y += ls }
        rule.lineWidth = 0.8; rule.stroke()

        // Margin
        NSColor(calibratedRed: 0.86, green: 0.0, blue: 0.0, alpha: 0.14).setStroke()
        let margin = NSBezierPath()
        let mx = CGFloat(maxDim) * 92.0 / 900.0
        margin.move(to: NSPoint(x: mx, y: 0)); margin.line(to: NSPoint(x: mx, y: size.height))
        margin.lineWidth = 0.8; margin.stroke()

        // Problem (handwriting font)
        let tf = handwritingFont(size: titleSize)
        (fixture.problem as NSString).draw(at: NSPoint(x: mx + 20, y: topY), withAttributes: [
            .font: tf,
            .foregroundColor: NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.14, alpha: 1)
        ])

        // Subtext
        let df = handwritingFont(size: detailSize)
        (fixture.subText as NSString).draw(at: NSPoint(x: mx + 24, y: bottomY), withAttributes: [
            .font: df,
            .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.20, alpha: 0.88)
        ])

        // Category tag
        let cf = NSFont.systemFont(ofSize: max(8, detailSize * 0.5), weight: .light)
        (fixture.category as NSString).draw(at: NSPoint(x: size.width - 80, y: size.height - 24), withAttributes: [
            .font: cf,
            .foregroundColor: NSColor(calibratedRed: 0.86, green: 0.0, blue: 0.0, alpha: 0.25)
        ])

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not render \(fixture.name)")
        }
        try png.write(to: outputDir.appendingPathComponent("\(fixture.name)\(suffix).png"))
    }
}

print(outputDir.path)
print("Generated \(fixtures.count) fixtures * 3 sizes = \(fixtures.count * 3) images")
for f in fixtures { print("  [\(f.category)] \(f.name) -> expected: \(f.expected)") }
