import SpriteKit

/// A fish seen from above, drawn with shapes. The head points along +x.
final class FishNode: SKNode {

    struct Palette {
        let body: SKColor
        let fin: SKColor
        let spots: SKColor?

        static let all: [Palette] = [
            Palette(body: SKColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1), fin: SKColor(red: 1.00, green: 0.75, blue: 0.35, alpha: 0.85), spots: nil),            // goldfish
            Palette(body: SKColor(white: 0.97, alpha: 1), fin: SKColor(white: 1.0, alpha: 0.7), spots: SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1)),          // koi
            Palette(body: SKColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1), fin: SKColor(red: 1.00, green: 0.95, blue: 0.55, alpha: 0.8), spots: SKColor(white: 0.1, alpha: 1)), // yellow / black koi
            Palette(body: SKColor(red: 0.85, green: 0.15, blue: 0.20, alpha: 1), fin: SKColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 0.8), spots: SKColor(white: 1.0, alpha: 1)),  // red / white
            Palette(body: SKColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1), fin: SKColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 0.8), spots: nil),             // blue
        ]
    }

    let length: CGFloat
    private let tail = SKNode()
    private let pectoralLeft: SKShapeNode
    private let pectoralRight: SKShapeNode
    private var wigglePhase: CGFloat = 0

    // Motion state
    var heading: CGFloat = 0          // radians
    var swimSpeed: CGFloat = 0            // points per second
    var targetHeading: CGFloat = 0
    var targetSpeed: CGFloat = 0
    var isEntering = true

    init(length: CGFloat, palette: Palette) {
        self.length = length
        let w = length * 0.32

        pectoralLeft = FishNode.fin(width: w * 0.9, height: w * 0.45, color: palette.fin)
        pectoralRight = FishNode.fin(width: w * 0.9, height: w * 0.45, color: palette.fin)
        super.init()

        // Shadow on the "pond floor" for depth.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: length * 0.8, height: w))
        shadow.fillColor = SKColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: length * 0.06, y: -length * 0.10)
        shadow.zPosition = -2
        addChild(shadow)

        // Pectoral fins
        pectoralLeft.position = CGPoint(x: length * 0.12, y: w * 0.38)
        pectoralRight.position = CGPoint(x: length * 0.12, y: -w * 0.38)
        pectoralRight.yScale = -1
        pectoralLeft.zPosition = -1
        pectoralRight.zPosition = -1
        addChild(pectoralLeft)
        addChild(pectoralRight)

        // Tail (pivots at the back of the body)
        tail.position = CGPoint(x: -length * 0.30, y: 0)
        tail.zPosition = -1
        let tailPath = CGMutablePath()
        tailPath.move(to: .zero)
        tailPath.addCurve(to: CGPoint(x: -length * 0.30, y: w * 0.75),
                          control1: CGPoint(x: -length * 0.10, y: w * 0.10),
                          control2: CGPoint(x: -length * 0.22, y: w * 0.70))
        tailPath.addQuadCurve(to: CGPoint(x: -length * 0.30, y: -w * 0.75),
                              control: CGPoint(x: -length * 0.18, y: 0))
        tailPath.addCurve(to: .zero,
                          control1: CGPoint(x: -length * 0.22, y: -w * 0.70),
                          control2: CGPoint(x: -length * 0.10, y: -w * 0.10))
        let tailShape = SKShapeNode(path: tailPath)
        tailShape.fillColor = palette.fin
        tailShape.strokeColor = .clear
        tail.addChild(tailShape)
        addChild(tail)

        // Body: teardrop, fat at the head end.
        let bodyPath = CGMutablePath()
        let nose = CGPoint(x: length * 0.38, y: 0)
        let back = CGPoint(x: -length * 0.34, y: 0)
        bodyPath.move(to: nose)
        bodyPath.addCurve(to: back,
                          control1: CGPoint(x: length * 0.36, y: w * 0.62),
                          control2: CGPoint(x: -length * 0.10, y: w * 0.55))
        bodyPath.addCurve(to: nose,
                          control1: CGPoint(x: -length * 0.10, y: -w * 0.55),
                          control2: CGPoint(x: length * 0.36, y: -w * 0.62))
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = palette.body
        body.strokeColor = palette.body.withAlphaComponent(0.6)
        body.lineWidth = 1
        addChild(body)

        // Dorsal stripe / highlight
        let ridge = SKShapeNode(ellipseOf: CGSize(width: length * 0.45, height: w * 0.18))
        ridge.fillColor = SKColor(white: 1, alpha: 0.25)
        ridge.strokeColor = .clear
        ridge.position = CGPoint(x: -length * 0.02, y: 0)
        body.addChild(ridge)

        if let spotColor = palette.spots {
            for _ in 0..<Int.random(in: 2...4) {
                let s = CGFloat.random(in: w * 0.25...w * 0.5)
                let spot = SKShapeNode(ellipseOf: CGSize(width: s * 1.4, height: s))
                spot.fillColor = spotColor
                spot.strokeColor = .clear
                spot.position = CGPoint(x: CGFloat.random(in: -length * 0.22...length * 0.22),
                                        y: CGFloat.random(in: -w * 0.18...w * 0.18))
                body.addChild(spot)
            }
        }

        // Eyes
        for side: CGFloat in [1, -1] {
            let eye = SKShapeNode(circleOfRadius: w * 0.11)
            eye.fillColor = .black
            eye.strokeColor = SKColor(white: 1, alpha: 0.8)
            eye.lineWidth = 1.5
            eye.position = CGPoint(x: length * 0.25, y: side * w * 0.27)
            body.addChild(eye)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func fin(width: CGFloat, height: CGFloat, color: SKColor) -> SKShapeNode {
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: -width, y: height), control: CGPoint(x: -width * 0.2, y: height * 1.2))
        p.addQuadCurve(to: .zero, control: CGPoint(x: -width * 0.6, y: height * 0.2))
        let n = SKShapeNode(path: p)
        n.fillColor = color
        n.strokeColor = .clear
        return n
    }

    /// Animate tail and fins. Faster swimming = faster, bigger wiggle.
    func animate(dt: CGFloat, turnRate: CGFloat) {
        let effort = min(1.6, 0.35 + swimSpeed / 220)
        wigglePhase += dt * (5 + effort * 9)
        let amp: CGFloat = 0.25 + effort * 0.25
        // Tail swings with the beat and bends into turns.
        tail.zRotation = sin(wigglePhase) * amp - turnRate * 0.25
        let finBeat = sin(wigglePhase * 0.5) * 0.35
        pectoralLeft.zRotation = finBeat
        pectoralRight.zRotation = -finBeat
    }
}
