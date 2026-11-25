import SpriteKit

/// The pond: one fish swims about; touching it makes a splash and a new fish arrives from an edge.
/// Every few minutes the fish swims away on its own and a different one swims in (the only change on Apple TV).
final class PondScene: SKScene {

    private var fish: FishNode?
    private var lastUpdate: TimeInterval = 0
    private var nextDecision: TimeInterval = 0
    private var spawnPending = false

    // Timed swaps
    private var fishAge: CGFloat = 0
    private var swapAfter: CGFloat = 0
    private var exitEdge = -1           // edge the last fish left by; the next one enters elsewhere
    private var lastPalette = -1

    /// Seconds before a fish swims away by itself. Override for testing with the launch argument `-swapSeconds 10`.
    private func randomSwapTime() -> CGFloat {
        let override = UserDefaults.standard.double(forKey: "swapSeconds")
        return override > 0 ? CGFloat(override) : .random(in: 120...240)
    }

    private var fishLength: CGFloat { min(size.width, size.height) * 0.17 }
    private var margin: CGFloat { fishLength * 0.9 }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.05, green: 0.32, blue: 0.40, alpha: 1)
        #if os(iOS)
        view.isMultipleTouchEnabled = true
        #endif
        buildWater()
        spawnFish()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard view != nil else { return }
        children.filter { $0.name == "water" }.forEach { $0.removeFromParent() }
        buildWater()
    }

    // MARK: - Background

    private func buildWater() {
        let water = SKNode()
        water.name = "water"
        water.zPosition = -10
        addChild(water)

        // Soft drifting light patches (caustics-ish).
        for _ in 0..<14 {
            let r = CGFloat.random(in: 60...220)
            let blob = SKShapeNode(ellipseOf: CGSize(width: r * 1.6, height: r))
            blob.fillColor = SKColor(red: 0.4, green: 0.85, blue: 0.85, alpha: CGFloat.random(in: 0.04...0.09))
            blob.strokeColor = .clear
            blob.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
            blob.zRotation = .random(in: 0...(.pi))
            water.addChild(blob)
            let dx = CGFloat.random(in: -80...80), dy = CGFloat.random(in: -80...80)
            let t = TimeInterval.random(in: 6...12)
            let drift = SKAction.sequence([
                .group([.moveBy(x: dx, y: dy, duration: t), .rotate(byAngle: 0.5, duration: t), .scale(to: 1.25, duration: t)]),
                .group([.moveBy(x: -dx, y: -dy, duration: t), .rotate(byAngle: -0.5, duration: t), .scale(to: 1.0, duration: t)]),
            ])
            drift.timingMode = .easeInEaseOut
            blob.run(.repeatForever(drift))
        }

        // A few pebbles on the bottom.
        for _ in 0..<25 {
            let r = CGFloat.random(in: 6...22)
            let pebble = SKShapeNode(ellipseOf: CGSize(width: r * 1.4, height: r))
            pebble.fillColor = SKColor(red: 0.05, green: 0.22, blue: 0.27, alpha: 0.6)
            pebble.strokeColor = .clear
            pebble.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
            pebble.zRotation = .random(in: 0...(.pi))
            water.addChild(pebble)
        }
    }

    // MARK: - Spawning

    private func spawnFish() {
        spawnPending = false
        let palettes = FishNode.Palette.all
        var paletteIndex = Int.random(in: 0..<palettes.count)
        if paletteIndex == lastPalette { paletteIndex = (paletteIndex + 1) % palettes.count }
        lastPalette = paletteIndex
        let f = FishNode(length: fishLength * CGFloat.random(in: 0.85...1.15), palette: palettes[paletteIndex])
        let off = fishLength
        var edge = Int.random(in: 0..<4)
        if edge == exitEdge { edge = (edge + 1 + Int.random(in: 0..<3)) % 4 }
        switch edge {
        case 0: f.position = CGPoint(x: -off, y: .random(in: size.height * 0.2...size.height * 0.8))
        case 1: f.position = CGPoint(x: size.width + off, y: .random(in: size.height * 0.2...size.height * 0.8))
        case 2: f.position = CGPoint(x: .random(in: size.width * 0.2...size.width * 0.8), y: -off)
        default: f.position = CGPoint(x: .random(in: size.width * 0.2...size.width * 0.8), y: size.height + off)
        }
        // Aim at a random point in the middle area.
        let target = CGPoint(x: .random(in: size.width * 0.3...size.width * 0.7),
                             y: .random(in: size.height * 0.3...size.height * 0.7))
        f.heading = atan2(target.y - f.position.y, target.x - f.position.x)
        f.targetHeading = f.heading
        f.swimSpeed = 180
        f.targetSpeed = 180
        f.isEntering = true
        f.zRotation = f.heading
        addChild(f)
        fish = f
        fishAge = 0
        swapAfter = randomSwapTime()
        nextDecision = lastUpdate + 1.5
    }

    /// Send the fish off through the nearest edge (0 left, 1 right, 2 bottom, 3 top).
    private func beginLeaving(_ f: FishNode) {
        let distances = [f.position.x, size.width - f.position.x, f.position.y, size.height - f.position.y]
        let edge = distances.indices.min { distances[$0] < distances[$1] }!
        let headings: [CGFloat] = [.pi, 0, -.pi / 2, .pi / 2]
        exitEdge = edge
        f.isLeaving = true
        f.targetHeading = headings[edge] + .random(in: -0.4...0.4)
        f.targetSpeed = .random(in: 160...240)
    }

    private func fishLeft(_ f: FishNode) {
        f.removeFromParent()
        fish = nil
        spawnPending = true
        run(.sequence([.wait(forDuration: .random(in: 1.5...3.5)), .run { [weak self] in self?.spawnFish() }]))
    }

    // MARK: - Touch

    #if os(iOS) || os(visionOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            ripple(at: p, strength: 0.5)
            if let f = fish, hypot(p.x - f.position.x, p.y - f.position.y) < f.length * 0.75 {
                catchFish(f)
            } else if let f = fish {
                startle(f, from: p)
            }
        }
    }

    #endif

    private func catchFish(_ f: FishNode) {
        fish = nil
        splash(at: f.position)
        f.run(.sequence([
            .group([.scale(to: 0.2, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
        spawnPending = true
        run(.sequence([.wait(forDuration: .random(in: 0.8...1.8)), .run { [weak self] in self?.spawnFish() }]))
    }

    /// A near miss makes the fish dart away from the paw.
    private func startle(_ f: FishNode, from p: CGPoint) {
        // Fish crossing the edge keep their course, or they could get stuck off screen.
        guard !f.isEntering, !f.isLeaving else { return }
        let d = hypot(p.x - f.position.x, p.y - f.position.y)
        guard d < f.length * 2.5 else { return }
        f.targetHeading = atan2(f.position.y - p.y, f.position.x - p.x) + .random(in: -0.5...0.5)
        f.targetSpeed = .random(in: 450...600)
        nextDecision = lastUpdate + 0.6
    }

    // MARK: - Effects

    private func ripple(at p: CGPoint, strength: CGFloat) {
        for i in 0..<(strength > 0.7 ? 3 : 1) {
            let ring = SKShapeNode(circleOfRadius: 20)
            ring.strokeColor = SKColor(white: 1, alpha: 0.6)
            ring.lineWidth = 3
            ring.fillColor = .clear
            ring.position = p
            ring.zPosition = 5
            ring.setScale(0.3)
            addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(i) * 0.12),
                .group([.scale(to: 3 + strength * 4, duration: 0.7), .fadeOut(withDuration: 0.7)]),
                .removeFromParent(),
            ]))
        }
    }

    private func splash(at p: CGPoint) {
        ripple(at: p, strength: 1)
        for _ in 0..<14 {
            let drop = SKShapeNode(circleOfRadius: .random(in: 4...9))
            drop.fillColor = SKColor(white: 1, alpha: 0.85)
            drop.strokeColor = .clear
            drop.position = p
            drop.zPosition = 6
            addChild(drop)
            let a = CGFloat.random(in: 0...(2 * .pi)), dist = CGFloat.random(in: 50...150)
            let move = SKAction.moveBy(x: cos(a) * dist, y: sin(a) * dist, duration: 0.45)
            move.timingMode = .easeOut
            drop.run(.sequence([.group([move, .fadeOut(withDuration: 0.45), .scale(to: 0.3, duration: 0.45)]), .removeFromParent()]))
        }
    }

    // MARK: - Swimming

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20))
        lastUpdate = currentTime
        guard let f = fish else {
            if !spawnPending { spawnFish() }
            return
        }

        fishAge += dt

        if f.isLeaving {
            let off = f.length
            if f.position.x < -off || f.position.x > size.width + off ||
               f.position.y < -off || f.position.y > size.height + off {
                fishLeft(f)
                return
            }
        } else if f.isEntering {
            if f.position.x > margin, f.position.x < size.width - margin,
               f.position.y > margin, f.position.y < size.height - margin {
                f.isEntering = false
            }
        } else if fishAge >= swapAfter {
            beginLeaving(f)
        } else {
            // Wander: every so often pick a new direction and pace.
            if currentTime >= nextDecision {
                f.targetHeading = f.heading + .random(in: -1.6...1.6)
                let r = Double.random(in: 0...1)
                if r < 0.15 {
                    f.targetSpeed = .random(in: 0...25)            // pause and hover
                    nextDecision = currentTime + .random(in: 0.6...1.8)
                } else if r < 0.40 {
                    f.targetSpeed = .random(in: 380...560)         // dart!
                    nextDecision = currentTime + .random(in: 0.4...0.9)
                } else {
                    f.targetSpeed = .random(in: 90...220)          // cruise
                    nextDecision = currentTime + .random(in: 1.0...3.0)
                }
            }
            // Steer back toward the middle when near an edge.
            let x = f.position.x, y = f.position.y
            if x < margin || x > size.width - margin || y < margin || y > size.height - margin {
                let center = CGPoint(x: size.width / 2 + .random(in: -100...100), y: size.height / 2 + .random(in: -100...100))
                f.targetHeading = atan2(center.y - y, center.x - x)
                f.targetSpeed = max(f.targetSpeed, 140)
            }
        }

        // Turn smoothly toward target heading.
        let diff = atan2(sin(f.targetHeading - f.heading), cos(f.targetHeading - f.heading))
        let maxTurn = (2.5 + f.swimSpeed / 150) * dt
        let turn = max(-maxTurn, min(maxTurn, diff))
        f.heading += turn
        let turnRate = dt > 0 ? turn / dt : 0

        // Ease speed (accelerate fast, slow down gently).
        let k: CGFloat = f.targetSpeed > f.swimSpeed ? 6 : 1.5
        f.swimSpeed += (f.targetSpeed - f.swimSpeed) * min(1, k * dt)

        f.position.x += cos(f.heading) * f.swimSpeed * dt
        f.position.y += sin(f.heading) * f.swimSpeed * dt
        f.zRotation = f.heading
        f.animate(dt: dt, turnRate: turnRate)
    }
}
