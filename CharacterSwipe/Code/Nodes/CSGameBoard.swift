import SpriteKit
import Foundation
import AVFoundation

class CSGameBoard: SKSpriteNode {
    weak var gameScene: CSGameScene!
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    var score_tile: SKSpriteNode!
    var score = 0
    var powerUpScore = 0
    let rows = 4
    let columns = 4
    let tileSideLength: CGFloat = 78
    let spacing: CGFloat = 7
    var gameBoardMatrix = [[2, 4, 8, 16],
                           [32, 64, 128, 256],
                           [512, 1024, 2048, 4096],
                           [8192, 0, 0, 0]]
    var tileMatrix = [[nil, nil, nil, nil],
                      [nil, nil, nil, nil],
                      [nil, nil, nil, nil],
                      [nil, nil, nil, nil]]
    var backgroundGrid = [[nil, nil, nil, nil],
                          [nil, nil, nil, nil],
                          [nil, nil, nil, nil],
                          [nil, nil, nil, nil]]
    var updatePowerup = false
    var powerUpNode = SKSpriteNode()
    var powerUpActive = false
    var cancelButton: SKSpriteNode?
    var powerUpType: String?
    var powerUpMultiplier = 250
    var progressBarBackground: SKSpriteNode!
    var progressBar: SKSpriteNode!
    private var audioPlayer: AVAudioPlayer?
    var merged = false
    var canSwipe = true
    var oldMaxValue = 4
    var oldBoard = [[0, 0, 0, 0],
                    [0, 0, 0, 0],
                    [0, 0, 0, 0],
                    [0, 0, 0, 0]]
    var gameOver = false
    var mergeSoundPlayed = false
    
    private var activeAudioPlayers: [AVAudioPlayer] = []
    private var preloadedSounds: [String: AVAudioPlayer] = [:]

    init(size: CGSize) {
        super.init(texture: nil, color: .clear, size: size)
        initializeBoardValues()
        setupGrid()
        updateTiles()
        self.isUserInteractionEnabled = true
        preloadSoundsInBackground()
        oldMaxValue = 4
        gameOver = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private func preloadSoundsInBackground() {
        DispatchQueue.global(qos: .background).async {
            let soundFiles = ["CS_swipeSound.mp3", "CS_mergeSound.mp3", "CS_lose.mp3","CS_powerup_press.mp3","CS_powerup_unlocked.mp3","CS_powerup_place.mp3","CS_powerup_delete.mp3","CS_powerup_2x.mp3"]
            for sound in soundFiles {
                if let url = Bundle.main.url(forResource: sound, withExtension: nil) {
                    do {
                        let player = try AVAudioPlayer(contentsOf: url)
                        player.prepareToPlay()
                        self.preloadedSounds[sound] = player
                        print("Preloaded sound: \(sound)")
                    } catch {
                        print("Error preloading sound \(sound): \(error)")
                    }
                }
            }
        }
    }

    private func playPreloadedSound(named name: String, volume: Float) {
        guard let player = preloadedSounds[name] else {
            print("Sound not found in preloaded list: \(name)")
            return
        }
        player.volume = volume
        player.play()
        
        // Thread-safe update of activeAudioPlayers
        DispatchQueue.main.async {
            self.activeAudioPlayers.append(player)
        }

        // Cleanup after playback
        DispatchQueue.global().asyncAfter(deadline: .now() + player.duration) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let index = self.activeAudioPlayers.firstIndex(of: player) {
                    self.activeAudioPlayers.remove(at: index)
                    print("Cleaned up audio player for: \(name)")
                }
            }
        }
    }


    func playSwipeSound() {
        playPreloadedSound(named: "CS_swipeSound.mp3", volume: 0.3)
    }

    func playMergeSound() {
        playPreloadedSound(named: "CS_mergeSound.mp3", volume: 0.2)
    }

    func playLoseSound() {
        playPreloadedSound(named: "CS_lose.mp3", volume: 0.4)
    }
    func playUnlockSound() {
        playPreloadedSound(named: "CS_powerup_unlocked.mp3", volume: 0.8)
    }
    func playPowerupSound() {
        playPreloadedSound(named: "CS_powerup_press.mp3", volume: 0.8)
    }
    func playPlaceSound() {
        playPreloadedSound(named: "CS_powerup_place.mp3", volume: 0.8)
    }
    func playDeleteSound() {
        playPreloadedSound(named: "CS_powerup_delete.mp3", volume: 0.8)
    }
    func playUpgradeSound() {
        playPreloadedSound(named: "CS_powerup_2x.mp3", volume: 0.8)
    }

    func boardMove(direction: String) -> [[Int]] {
        var gameBoard = gameBoardMatrix
        var mergedTiles = Array(repeating: Array(repeating: false, count: columns), count: rows)

        func animateTileMove(from: (row: Int, col: Int), to: (row: Int, col: Int)) {
            if let tileNode = tileMatrix[from.row][from.col] as? SKSpriteNode {
                let moveAction = SKAction.move(to: calculateTilePosition(row: to.row, col: to.col), duration: 0.1)
                tileNode.run(moveAction)
                tileMatrix[to.row][to.col] = tileNode
                tileMatrix[from.row][from.col] = nil
            }
        }
//merge animation
        func animateTileMerge(at: (row: Int, col: Int), value: Int, oldTile: SKSpriteNode) {
            if let newTileNode = tileMatrix[at.row][at.col] as? SKSpriteNode {
                // Prepare haptic generator to reduce delay
                let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
                feedbackGenerator.prepare()

                // Ensure old tile moves below the new tile
                oldTile.zPosition = 0

                // Animation for the old tile to swipe into position
                let moveAction = SKAction.move(to: calculateTilePosition(row: at.row, col: at.col), duration: 0.1)
                let removeOldTile = SKAction.run {
                    oldTile.removeFromParent()
                }
                oldTile.run(SKAction.sequence([moveAction, removeOldTile]))

                // Bounce animation for the new tile
                let scaleUp = SKAction.scale(to: 1.2, duration: 0.03)
                let scaleDown = SKAction.scale(to: 1.0, duration: 0.03)
                let bounce = SKAction.sequence([scaleUp, scaleDown])

                // Fade out old texture to half opacity and fade in new texture
                let fadeOutOldTexture = SKAction.fadeAlpha(to: 0.5, duration: 0.03)
                let fadeInNewTexture = SKAction.fadeAlpha(to: 1.0, duration: 0.03)
                let updateTexture = SKAction.run {
                    newTileNode.texture = self.getTextureForValue(value)
                }
                
                if value > oldMaxValue {
                    oldMaxValue = value
                    print(oldMaxValue)
                }
                let textureChangeSequence = SKAction.sequence([fadeOutOldTexture, updateTexture, fadeInNewTexture])

                // Ensure tile returns to correct size
                let ensureCorrectSize = SKAction.scale(to: 1.0, duration: 0.0)

                // Trigger haptic feedback
                let triggerHaptic = SKAction.run {
                    feedbackGenerator.impactOccurred()
                }
                // Play merge sound action
                if !mergeSoundPlayed {
                    let playMergeSound = SKAction.playSoundFileNamed("CS_mergeSound.mp3",  waitForCompletion: false)
                    newTileNode.run(SKAction.sequence([bounce, textureChangeSequence, triggerHaptic, playMergeSound, ensureCorrectSize]))
                    mergeSoundPlayed = true
                }
                else {
                    newTileNode.run(SKAction.sequence([bounce, textureChangeSequence, triggerHaptic, ensureCorrectSize]))

                }
                delay(0.1) {
                    self.mergeSoundPlayed = false
                }
                // Run animations with texture fade to half opacity, sound, haptic feedback, and ensure correct size
            }
        }




        switch direction {
        case "right":
            oldBoard = gameBoard
            for r in 0..<rows {
                var target = columns - 1
                for c in stride(from: columns - 1, through: 0, by: -1) {
                    if gameBoard[r][c] != 0 {
                        if c != target {
                            gameBoard[r][target] = gameBoard[r][c]
                            gameBoard[r][c] = 0
                            animateTileMove(from: (r, c), to: (r, target))
                        }
                        if target < columns - 1, gameBoard[r][target] == gameBoard[r][target + 1], !mergedTiles[r][target + 1] {
                            let oldTile = tileMatrix[r][target] as! SKSpriteNode
                            gameBoard[r][target + 1] *= 2
                            gameBoard[r][target] = 0
                            score += gameBoard[r][target + 1]
                            updatePowerUps(scoreChange: gameBoard[r][target + 1])
                            mergedTiles[r][target + 1] = true
                            animateTileMerge(at: (r, target + 1), value: gameBoard[r][target + 1], oldTile: oldTile)
                            merged = true
                        } else {
                            target -= 1
                        }
                    }
                }
            }
        case "left":
            oldBoard = gameBoard
            for r in 0..<rows {
                var target = 0
                for c in 0..<columns {
                    if gameBoard[r][c] != 0 {
                        if c != target {
                            gameBoard[r][target] = gameBoard[r][c]
                            gameBoard[r][c] = 0
                            animateTileMove(from: (r, c), to: (r, target))
                        }
                        if target > 0, gameBoard[r][target] == gameBoard[r][target - 1], !mergedTiles[r][target - 1] {
                            let oldTile = tileMatrix[r][target] as! SKSpriteNode
                            gameBoard[r][target - 1] *= 2
                            gameBoard[r][target] = 0
                            score += gameBoard[r][target - 1]
                            updatePowerUps(scoreChange: gameBoard[r][target - 1])
                            mergedTiles[r][target - 1] = true
                            animateTileMerge(at: (r, target - 1), value: gameBoard[r][target - 1], oldTile: oldTile)
                            merged = true
                        } else {
                            target += 1
                        }
                    }
                }
            }
        case "up":
            oldBoard = gameBoard
            for c in 0..<columns {
                var target = 0
                for r in 0..<rows {
                    if gameBoard[r][c] != 0 {
                        if r != target {
                            gameBoard[target][c] = gameBoard[r][c]
                            gameBoard[r][c] = 0
                            animateTileMove(from: (r, c), to: (target, c))
                        }
                        if target > 0, gameBoard[target][c] == gameBoard[target - 1][c], !mergedTiles[target - 1][c] {
                            let oldTile = tileMatrix[target][c] as! SKSpriteNode
                            gameBoard[target - 1][c] *= 2
                            gameBoard[target][c] = 0
                            score += gameBoard[target - 1][c]
                            updatePowerUps(scoreChange: gameBoard[target - 1][c])
                            mergedTiles[target - 1][c] = true
                            animateTileMerge(at: (target - 1, c), value: gameBoard[target - 1][c], oldTile: oldTile)
                            merged = true
                        } else {
                            target += 1
                        }
                    }
                }
            }
        case "down":
            oldBoard = gameBoard
            for c in 0..<columns {
                var target = rows - 1
                for r in stride(from: rows - 1, through: 0, by: -1) {
                    if gameBoard[r][c] != 0 {
                        if r != target {
                            gameBoard[target][c] = gameBoard[r][c]
                            gameBoard[r][c] = 0
                            animateTileMove(from: (r, c), to: (target, c))
                        }
                        if target < rows - 1, gameBoard[target][c] == gameBoard[target + 1][c], !mergedTiles[target + 1][c] {
                            let oldTile = tileMatrix[target][c] as! SKSpriteNode
                            gameBoard[target + 1][c] *= 2
                            gameBoard[target][c] = 0
                            score += gameBoard[target + 1][c]
                            updatePowerUps(scoreChange: gameBoard[target + 1][c])
                            mergedTiles[target + 1][c] = true
                            animateTileMerge(at: (target + 1, c), value: gameBoard[target + 1][c], oldTile: oldTile)
                            merged = true
                        } else {
                            target -= 1
                        }
                    }
                }
            }
        default:
            break
        }
        if !merged && oldBoard != gameBoard {
            playSwipeSound()
        }
        merged = false

        return gameBoard
    }


    
    // Handle swipe input
    func onUserInput(direction: String) {
        if powerUpActive || !canSwipe {
            delay(0.1) {
                self.canSwipe = true
            }
            return
        }
        // Perform the actual move
        canSwipe = false
        let newBoard = boardMove(direction: direction)
        if newBoard != gameBoardMatrix {
            gameBoardMatrix = newBoard
            updateTiles()
            delay(0.08) {
                self.addRandomTile()
                self.updatePowerUps(scoreChange: 0)
            }
            
            delay(0.15) {self.canSwipe = true}
            gameScene.updateScoreLabel(newScore: score)
        }

        // Check for game over
        if !canMakeMove() && powerUpType != "XPowerup" && !gameOver {
            
            gameOver = true
            triggerLossHapticFeedback()
            playLoseSound()
            dimAllTiles()
            

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                
                updatePowerup = false
                powerUpNode.removeFromParent()
                score = 0
                progressBar.removeFromParent()
                gameScene.updateScoreLabel(newScore: score)
                
                for r in 0...3 {
                    for c in 0...3 {
                        if let tile = self.tileMatrix[r][c] as? SKSpriteNode {
                            tile.removeFromParent()
                        }
                    }
                }
                gameScene.context?.stateMachine?.enter(CSLoseState.self)
                print("Game Over -- attempting to transition to CSLoseState")
            }
        }
    }

    // Helper to check if any moves are possible
    private func canMakeMove() -> Bool {
        let originalBoard = gameBoardMatrix // Save current state

        // Test moves in all directions without modifying the actual game state
        for direction in ["left", "right", "up", "down"] {
            if boardMoveSimulated(direction: direction, board: originalBoard) != originalBoard {
                return true // A move is possible
            }
        }

        return false // No valid moves
    }

    func triggerLossHapticFeedback() {
        // Prepare haptic generators for a dramatic effect
        let heavyFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
        let rigidFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
        let softFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)

        // Prepare for reduced latency
        heavyFeedbackGenerator.prepare()
        rigidFeedbackGenerator.prepare()
        softFeedbackGenerator.prepare()

        // Trigger a sequence of haptic feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) {
            heavyFeedbackGenerator.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rigidFeedbackGenerator.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            softFeedbackGenerator.impactOccurred()
        }
        print("loss haptic")
    }

    
    
    // Simulate a move without modifying the actual game state
    private func boardMoveSimulated(direction: String, board: [[Int]]) -> [[Int]] {
        var simulatedBoard = board
        var mergedTiles = Array(repeating: Array(repeating: false, count: columns), count: rows)

        switch direction {
        case "right":
            for r in 0..<rows {
                for c in stride(from: columns - 1, through: 0, by: -1) {
                    if simulatedBoard[r][c] == 0 {
                        for k in stride(from: c - 1, through: 0, by: -1) {
                            if simulatedBoard[r][k] != 0 {
                                simulatedBoard[r][c] = simulatedBoard[r][k]
                                simulatedBoard[r][k] = 0
                                break
                            }
                        }
                    }
                    if c > 0, simulatedBoard[r][c] == simulatedBoard[r][c - 1], !mergedTiles[r][c] {
                        simulatedBoard[r][c] *= 2
                        simulatedBoard[r][c - 1] = 0
                        mergedTiles[r][c] = true
                    }
                }
            }
        case "left":
            for r in 0..<rows {
                for c in 0..<columns {
                    if simulatedBoard[r][c] == 0 {
                        for k in (c + 1)..<columns {
                            if simulatedBoard[r][k] != 0 {
                                simulatedBoard[r][c] = simulatedBoard[r][k]
                                simulatedBoard[r][k] = 0
                                break
                            }
                        }
                    }
                    if c < columns - 1, simulatedBoard[r][c] == simulatedBoard[r][c + 1], !mergedTiles[r][c] {
                        simulatedBoard[r][c] *= 2
                        simulatedBoard[r][c + 1] = 0
                        mergedTiles[r][c] = true
                    }
                }
            }
        case "up":
            for c in 0..<columns {
                for r in 0..<rows {
                    if simulatedBoard[r][c] == 0 {
                        for k in (r + 1)..<rows {
                            if simulatedBoard[k][c] != 0 {
                                simulatedBoard[r][c] = simulatedBoard[k][c]
                                simulatedBoard[k][c] = 0
                                break
                            }
                        }
                    }
                    if r < rows - 1, simulatedBoard[r][c] == simulatedBoard[r + 1][c], !mergedTiles[r][c] {
                        simulatedBoard[r][c] *= 2
                        simulatedBoard[r + 1][c] = 0
                        mergedTiles[r][c] = true
                    }
                }
            }
        case "down":
            for c in 0..<columns {
                for r in stride(from: rows - 1, through: 0, by: -1) {
                    if simulatedBoard[r][c] == 0 {
                        for k in stride(from: r - 1, through: 0, by: -1) {
                            if simulatedBoard[k][c] != 0 {
                                simulatedBoard[r][c] = simulatedBoard[k][c]
                                simulatedBoard[k][c] = 0
                                break
                            }
                        }
                    }
                    if r > 0, simulatedBoard[r][c] == simulatedBoard[r - 1][c], !mergedTiles[r][c] {
                        simulatedBoard[r][c] *= 2
                        simulatedBoard[r - 1][c] = 0
                        mergedTiles[r][c] = true
                    }
                }
            }
        default:
            break
        }

        return simulatedBoard
    }

    
    func setupGrid() {
        updateProgressBar()
        for row in 0..<rows {
            for col in 0..<columns {
                if tileMatrix[row][col] != nil {
                    (tileMatrix[row][col] as! SKSpriteNode).removeFromParent()
                    tileMatrix[row][col] = nil
                }
                // Create a static background node for each position
                backgroundGrid[row][col] = SKSpriteNode(texture: getTextureForValue(0), size: CGSize(width: tileSideLength, height: tileSideLength))
                (backgroundGrid[row][col] as! SKSpriteNode).position = calculateTilePosition(row: row, col: col)
                (backgroundGrid[row][col] as! SKSpriteNode).zPosition = -1 // Place it behind everything
                addChild((backgroundGrid[row][col] as! SKSpriteNode))

                // Initialize the tileMatrix with SKSpriteNodes where needed
                let tileValue = gameBoardMatrix[row][col]
                if tileValue > 0 {
                    let tileNode = SKSpriteNode(texture: getTextureForValue(tileValue))
                    tileNode.position = calculateTilePosition(row: row, col: col)
                    tileNode.size = CGSize(width: tileSideLength, height: tileSideLength)
                    tileMatrix[row][col] = tileNode
                    addChild(tileNode)
                }
            }
        }
    }

    
    private func calculateTilePosition(row: Int, col: Int) -> CGPoint {
        //6.9 inch iphone
        if UIScreen.main.bounds.width == 440 {
            let gridWidth = CGFloat(columns) * (tileSideLength + spacing) - spacing
            let gridHeight = CGFloat(rows) * (tileSideLength + spacing) - spacing
            let xPosition = CGFloat(col) * (tileSideLength + spacing) - gridWidth / 2 + tileSideLength / 2
            let yPosition = (CGFloat(3-row) * (tileSideLength + spacing) - gridHeight / 2 + tileSideLength / 2)-108
            return CGPoint(x: xPosition, y: yPosition)
        }
        //6.7 inch iphone
        else if UIScreen.main.bounds.width == 430 {
            let gridWidth = CGFloat(columns) * (tileSideLength + spacing) - spacing
            let gridHeight = CGFloat(rows) * (tileSideLength + spacing) - spacing
            let xPosition = CGFloat(col) * (tileSideLength + spacing) - gridWidth / 2 + tileSideLength / 2
            let yPosition = (CGFloat(3-row) * (tileSideLength + spacing) - gridHeight / 2 + tileSideLength / 2)-105
            return CGPoint(x: xPosition, y: yPosition)
        }
        // iphone se
        else if UIScreen.main.bounds.width < 380 {
            print("iphone se")
            let gridWidth = CGFloat(columns) * (tileSideLength + spacing) - spacing
            let gridHeight = CGFloat(rows) * (tileSideLength + spacing) - spacing
            let xPosition = CGFloat(col) * (tileSideLength + spacing) - gridWidth / 2 + tileSideLength / 2
            let yPosition = (CGFloat(3-row) * (tileSideLength + spacing) - gridHeight / 2 + tileSideLength / 2)-76
            return CGPoint(x: xPosition, y: yPosition)
        }
        //6.1 inch iphone
        else if UIScreen.main.bounds.width == 393 {
            let gridWidth = CGFloat(columns) * (tileSideLength + spacing) - spacing
            let gridHeight = CGFloat(rows) * (tileSideLength + spacing) - spacing
            let xPosition = CGFloat(col) * (tileSideLength + spacing) - gridWidth / 2 + tileSideLength / 2
            let yPosition = (CGFloat(3-row) * (tileSideLength + spacing) - gridHeight / 2 + tileSideLength / 2)-97
            return CGPoint(x: xPosition, y: yPosition)
        }
        //6.3 inch iphone
        else{
            let gridWidth = CGFloat(columns) * (tileSideLength + spacing) - spacing
            let gridHeight = CGFloat(rows) * (tileSideLength + spacing) - spacing
            let xPosition = CGFloat(col) * (tileSideLength + spacing) - gridWidth / 2 + tileSideLength / 2
            let yPosition = (CGFloat(3-row) * (tileSideLength + spacing) - gridHeight / 2 + tileSideLength / 2)-100
            return CGPoint(x: xPosition, y: yPosition)
        }
    }
    
    func calculatePowerupPosition() -> CGPoint {
        //6.1 inch iphone
        if UIScreen.main.bounds.width == 393 {
            return CGPoint(x: size.width / 3.5, y: size.height / 1.70)
        }
        //6.9 inch iphone
        else if UIScreen.main.bounds.width == 440 {
            return CGPoint(x: size.width / 3.5, y: size.height / 1.52)
        }
        // iphone se
        else if UIScreen.main.bounds.width < 380 {
            print("iphone se")
            return CGPoint(x: size.width / 3.5, y: size.height / 1.60)
        }
        //6.7 inch iphone
        else if UIScreen.main.bounds.width == 430 {
            return CGPoint(x: size.width / 3.5, y: size.height / 1.55)
        }
        //6.3 inch iphone
        else{
            return CGPoint(x: size.width / 3.5, y: size.height / 1.65)
        }
    }
    
    // Update tiles on the board (with animation)
    func updateTiles() {
        for row in 0..<rows {
            for col in 0..<columns {
                let tileName = "tile_\(row)_\(col)"
                if let tileNode = childNode(withName: tileName) as? SKSpriteNode {
                    let value = gameBoardMatrix[row][col]
                    
                    // Set texture or skip for empty tiles
                    tileNode.texture = getTextureForValue(value)
                    
                    // Skip movement for empty tiles
                    if value == 0 { continue }
                    
                    // Animate only if position changes
                    let targetPosition = calculateTilePosition(row: row, col: col)
                    if tileNode.position != targetPosition {
                        let moveAction = SKAction.move(to: targetPosition, duration: 0.05)
                        tileNode.run(moveAction)
                    }
                }
            }
        }
    }
    
    // Initialize board values (no changes)
    func initializeBoardValues() {
        gameOver = false
        gameScene?.resetTileOpacity()
        score = 0
        powerUpScore = 0
        powerUpMultiplier = 250
        setupProgressBar()
        updateProgressBar()
        self.gameBoardMatrix = [[0, 0, 0, 0],
                                [0, 0, 0, 0],
                                [0, 0, 0, 0],
                                [0, 0, 0, 0]]
        let randomRow = Int.random(in: 0..<3)
        let randomColumn = Int.random(in: 0..<3)
        gameBoardMatrix[randomRow][randomColumn] = [2, 4].randomElement()!
        tileMatrix[randomRow][randomColumn] = SKSpriteNode(texture: getTextureForValue(gameBoardMatrix[randomRow][randomColumn]))
        (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).zPosition = 1
        while(true) {
            let randomRow = Int.random(in: 0..<3)
            let randomColumn = Int.random(in: 0..<3)
            if gameBoardMatrix[randomRow][randomColumn] == 0 {
                gameBoardMatrix[randomRow][randomColumn] = [2, 4].randomElement()!
                tileMatrix[randomRow][randomColumn] = SKSpriteNode(texture: getTextureForValue(gameBoardMatrix[randomRow][randomColumn]))
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).zPosition = 1
                break
            }
        }
    }
    
    // Add a random tile to an empty space (no changes)
    func addRandomTile() {
        while true {
            let randomRow = Int.random(in: 0..<4)
            let randomColumn = Int.random(in: 0..<4)
            if gameBoardMatrix[randomRow][randomColumn] == 0 {
                // Assign a random value to the tile (e.g., 2 or 4)
                gameBoardMatrix[randomRow][randomColumn] = [2, 2, 2, 2, 2, 2, 2, 2, 2, 4].randomElement()!

                // Create the new tile node
                tileMatrix[randomRow][randomColumn] = SKSpriteNode(texture: getTextureForValue(gameBoardMatrix[randomRow][randomColumn]))
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).position = calculateTilePosition(row: randomRow, col: randomColumn)
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).zPosition = 1
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).size = CGSize(width: tileSideLength, height: tileSideLength)
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).setScale(0.5) // Start at a scale of 0.5
                addChild(tileMatrix[randomRow][randomColumn] as! SKSpriteNode)

                // Scale animation to grow the tile from 0.5 to full size, with continuous correction to cap size
                let scaleUp = SKAction.scale(to: 1.0, duration: 0.07)
                let restrictScale = SKAction.customAction(withDuration: 0.07) { node, elapsedTime in
                    if node.xScale > 1.0 || node.yScale > 1.0 {
                        node.setScale(1.0)
                    }
                }
                let group = SKAction.group([scaleUp, restrictScale])
                (tileMatrix[randomRow][randomColumn] as! SKSpriteNode).run(group)

                break
            }
        }
    }



    
    // Return texture based on value (no changes)
    func getTextureForValue(_ value: Int) -> SKTexture? {
        let tileTextures: [Int: String] = [
            0: "CS_tile_0",
            2: "CS_tile_1",
            4: "CS_tile_2",
            8: "CS_tile_3",
            16: "CS_tile_4",
            32: "CS_tile_5",
            64: "CS_tile_6",
            128: "CS_tile_7",
            256: "CS_tile_8",
            512: "CS_tile_9",
            1024: "CS_tile_10",
            2048: "CS_tile_11",
            4096: "CS_tile_12",
            8192: "CS_tile_13",
        ]
        if let textureName = tileTextures[value] {
            return SKTexture(imageNamed: textureName)
        }
        return nil
    }
    
    func removeTile(atRow row: Int, column col: Int) {
        guard let tile = tileMatrix[row][col] as? SKSpriteNode else { return }
        
        // Animate the tile shrinking out
        let shrinkOut = SKAction.scale(to: 0.0, duration: 0.3) // Shrink to 0 over 0.3 seconds
        shrinkOut.timingMode = .easeInEaseOut // Smooth shrinking animation
        
        // Remove the tile after shrinking
        let removeAction = SKAction.removeFromParent()
        let shrinkAndRemove = SKAction.sequence([shrinkOut, removeAction])
        
        // Run the shrink and remove sequence
        tile.run(shrinkAndRemove) {
            // Clean up the game board matrix and tile matrix
            self.gameBoardMatrix[row][col] = 0
            self.tileMatrix[row][col] = nil
        }
    }

    func upgradeTile(atRow row: Int, column col: Int) {
        guard let tile = tileMatrix[row][col] as? SKSpriteNode else { return }
        
        // Define the shrink action (instant shrink)
        let shrink = SKAction.scale(to: 0.0, duration: 0.1)
        
        // Action to update the texture after shrinking
        let updateTexture = SKAction.run {
            self.gameBoardMatrix[row][col] *= 2
            tile.texture = self.getTextureForValue(self.gameBoardMatrix[row][col])
        }
        
        // Define the scale-up action (grow back smoothly)
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.2)
        scaleUp.timingMode = .easeOut // Smooth growth animation
        let resetSize = SKAction.scale(to: 1.0, duration: 0)
        
        // Sequence: Shrink -> Update Texture -> Scale Back Up
        let shrinkAndGrow = SKAction.sequence([shrink, updateTexture, scaleUp, resetSize])
        
        // Run the animation
        tile.run(shrinkAndGrow)
        }

    func getPositionsBelowSecondHighest(matrix: [[Int?]]) -> [(row: Int, col: Int)] {
        var max = 0
        for r in 0..<rows {
            for c in 0..<columns {
                if gameBoardMatrix[r][c] > max {
                    max = gameBoardMatrix[r][c]
                }
            }
        }
        let secondHighest = max / 2
        // Collect all positions with values below the second highest
        var positions: [(row: Int, col: Int)] = []
        for row in 0..<matrix.count {
            for col in 0..<matrix[row].count {
                if let value = matrix[row][col], value < secondHighest {
                    positions.append((row: row, col: col))
                }
            }
        }
        
        return positions
    }
    
    func updatePowerUps(scoreChange: Int) {
        if powerUpScore < powerUpMultiplier && powerUpScore + scoreChange >= powerUpMultiplier {
            playUnlockSound()
            let mynum = Int.random(in: 0...2)
            progressBarBackground.isHidden = true

            if mynum == 0 {
                print("x powerup")
                powerUpNode = SKSpriteNode(imageNamed: "CS_delete_powerup")
                powerUpType = "XPowerup"
            } else if mynum == 1 {
                print("")
                powerUpNode = SKSpriteNode(imageNamed: "CS_2xPowerup")
                powerUpType = "2xPowerup"
            } else if maxValue() >= 8 {
                print("Should do place tile image")
                powerUpNode = SKSpriteNode(imageNamed: "CS_place_tile"+String(maxValue()/4))
                powerUpType = "TileAddPowerup"
                updatePowerup = true
            } else {
                updatePowerUps(scoreChange: scoreChange)
                return
            }

            // Set up power-up node properties
            powerUpNode.size = CGSize(width: size.width / 5, height: size.width / 5)
            powerUpNode.position = calculatePowerupPosition()
            powerUpNode.zPosition = 10
            powerUpNode.setScale(0) // Start with scale 0 for animation
            addChild(powerUpNode)
            delay(0.1) {
                print("powerup should glow")
                let glow = SKShapeNode(rectOf: CGSize(width: 65, height: 65), cornerRadius: 10)
                glow.strokeColor = .white
                glow.lineWidth = 2.0
                glow.glowWidth = 3.0
                glow.zPosition = self.powerUpNode.zPosition + 1
                glow.alpha = 0
                self.powerUpNode.addChild(glow)
                let fadeIn = SKAction.fadeAlpha(to: 0.3, duration: 1)
                let fadeOut = SKAction.fadeAlpha(to: 0.0, duration: 1)
                let pulse = SKAction.sequence([fadeIn, fadeOut])
                glow.run(SKAction.repeatForever(pulse))
            }
            // Shrink the progress bar before showing the power-up
            let shrinkProgressBar = SKAction.scaleY(to: 0, duration: 0.3)
            let switchToPowerUp = SKAction.run {
                // Hide progress bar and switch to power-up node
                self.progressBarBackground.isHidden = true
                self.powerUpNode.isHidden = false
            }
            
            // Grow the power-up after it appears
            let growPowerUp = SKAction.scale(to: 1.0, duration: 0.3)
            
            let sequence = SKAction.sequence([shrinkProgressBar, switchToPowerUp, growPowerUp])
            powerUpNode.run(sequence)
            
            powerUpScore += scoreChange
        } else {
            powerUpScore += scoreChange
            updateProgressBar()
        }

        if updatePowerup {
            powerUpNode.texture = SKTexture(imageNamed: "CS_place_tile" + String(maxValue()/4))
        }
    }
    
    func maxValue() -> Int {
        var maxValue = 0
        for r in 0..<4 {
            for c in 0..<4 {
                if gameBoardMatrix[r][c] > maxValue {
                    maxValue = gameBoardMatrix[r][c]
                }
            }
        }
        return maxValue
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        handleTouch(at: location)
    }
    
    func isZero() -> Bool {
        for c in 0...3 {
            for r in 0...3 {
                if gameBoardMatrix[c][r] == 0 {return true}
            }
        }
        return false
    }
    
    func activatePowerUp() {
        if powerUpType == "TileAddPowerup" && !isZero() {return}
        powerUpNode.removeAllChildren()
        powerUpActive = true

        // Call specific power-up function based on the type
        if powerUpType == "XPowerup" {
            handleXPowerUp()
        } else if powerUpType == "2xPowerup" {
            handle2xPowerUp()
        } else {
            handleTileAddPowerUp()
        }

        // Grey out tiles that can't have the power-up applied
        for row in 0..<rows {
            for col in 0..<columns {
                guard let tileNode = tileMatrix[row][col] as? SKSpriteNode else { continue }

                let value = gameBoardMatrix[row][col]
                let isEligible: Bool

                // Determine eligibility based on the power-up type
                if powerUpType == "XPowerup" {
                    isEligible = value < maxValue() / 2 && value > 0
                } else if powerUpType == "2xPowerup" {
                    isEligible = value < maxValue() / 2 && value > 0
                } else if powerUpType == "TileAddPowerup" {
                    isEligible = value == 0
                } else {
                    isEligible = false
                }

                if !isEligible {
                    // Grey out non-eligible tiles
                    let fadeToAlpha = SKAction.fadeAlpha(to: 0.3, duration: 0.1)
                    tileNode.run(fadeToAlpha)

                }
            }
        }

        // Handle animations for eligible tiles
        let positionsBelowSecondHighest = getPositionsBelowSecondHighest(matrix: gameBoardMatrix)

        if powerUpType != "TileAddPowerup" {
            for position in positionsBelowSecondHighest {
                progressBar.isHidden = true
                progressBarBackground.isHidden = true
                guard let tileNode = tileMatrix[position.row][position.col] as? SKSpriteNode else { continue }
                let originalSize = tileNode.size

                // Create a pulsing effect for eligible tiles
                let scaleUp = SKAction.scale(to: 1, duration: 0.5)
                let scaleDown = SKAction.scale(to: 0.9, duration: 0.5)
                let pulse = SKAction.sequence([scaleDown, scaleUp])
                let pulsingAction = SKAction.repeatForever(pulse)
                tileNode.run(pulsingAction)

                // Store the original size for later restoration
                tileNode.userData = ["originalSize": originalSize]
            }
        } else {
            // Highlight empty tiles for TileAddPowerup
            for r in 0...3 {
                for c in 0...3 {
                    if gameBoardMatrix[r][c] == 0 {
                        let tileNode = backgroundGrid[r][c] as! SKSpriteNode

                        // Set the texture for the tile
                        tileNode.texture = getTextureForValue(maxValue() / 4)

                        // Start with 0 opacity
                        tileNode.alpha = 0

                        // Define the fade-in and fade-out actions
                        let tileFadeIn = SKAction.fadeAlpha(to: 0.8, duration: 0.5) // Fade in over 0.5 seconds
                        let tileFadeOut = SKAction.fadeAlpha(to: 0.5, duration: 0.5) // Fade out over 0.5 seconds

                        // Sequence to fade in and out
                        let fadeSequence = SKAction.sequence([tileFadeIn, tileFadeOut])

                        // Repeat the sequence forever
                        tileNode.run(SKAction.repeatForever(fadeSequence))

                        // Create a glowing blue border effect
                        let blueGlow = SKShapeNode(rectOf: tileNode.size, cornerRadius: 10)
                        blueGlow.strokeColor = .white
                        blueGlow.lineWidth = 2.0
                        blueGlow.glowWidth = 6.0
                        blueGlow.zPosition = tileNode.zPosition + 1
                        blueGlow.alpha = 0
                        tileNode.addChild(blueGlow)

                        // Create a pulsing opacity animation
                        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 1)
                        let fadeIn = SKAction.fadeAlpha(to: 0.3, duration: 1)
                        let pulse = SKAction.sequence([fadeIn, fadeOut])
                        blueGlow.run(SKAction.repeatForever(pulse))
                        
                        
                    }
                }
            }
        }

        // Add cancel button
        addCancelButton()
    }



    // Add cancel button to the board
    func addCancelButton() {
        powerUpNode.isHidden = true
        progressBar.isHidden = true
        progressBarBackground.isHidden = true
        // Create the cancel button
        cancelButton = SKSpriteNode(imageNamed: "CS_cancel")
        cancelButton?.size = CGSize(width: size.width / 5, height: size.width / 5)
        cancelButton?.position = calculatePowerupPosition()
        cancelButton?.zPosition = 10
        cancelButton?.name = "CancelButton"
        
        // Start at scale 0 (invisible)
        cancelButton?.setScale(0.0)

        // Add the button to the scene
        addChild(cancelButton!)
        
        // Create a scale animation to grow in
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.3)
        scaleUp.timingMode = .easeOut // Smooth growth effect
        
        // Run the animation
        cancelButton?.run(scaleUp)
    }


    func deactivatePowerUp() {
        progressBarBackground.isHidden = false
        progressBar.isHidden = false
        print("deactivate powerup")
        powerUpScore = 0
        powerUpMultiplier *= 2
        delay(0.7){self.powerUpActive = false}
        powerUpType = ""

        // Reset the opacity and animations of all tiles
        for row in 0..<4 {
            for col in 0..<4 {
                if let tileNode = tileMatrix[row][col] as? SKSpriteNode {
                    tileNode.setScale(1.0)
                    tileNode.removeAllActions() // Remove animations
                    let fadeToAlpha = SKAction.fadeAlpha(to: 1, duration: 0.5)
                    tileNode.run(fadeToAlpha)

                    // Restore the original size if previously modified
                    if let originalSize = tileNode.userData?["originalSize"] as? CGSize {
                        tileNode.size = originalSize
                    }
                }

                // Remove glowing effects for background tiles (TileAddPowerup)
                if let backgroundNode = backgroundGrid[row][col] as? SKSpriteNode {
                    backgroundNode.removeAllActions()
                    backgroundNode.children.forEach { $0.removeFromParent() } // Remove glowing effects
                }
            }
        }

        cancelButton?.removeFromParent()
        cancelButton = nil
        powerUpNode.removeFromParent()
        updateProgressBar()
    }

    // Specific power-up handlers (empty for now)
    func handleXPowerUp() {
        print("X Power-Up activated!")
        // Logic for X power-up
    }

    func handle2xPowerUp() {
        print("2x Power-Up activated!")
        // Logic for 2x power-up
    }

    func handleTileAddPowerUp() {
        print("Tile Add Power-Up activated!")
        // Logic for upgrading a tile
    }
}
extension CSGameBoard {
    func stopTileAnimations() {
        for r in 0..<rows {
            for c in 0..<columns {
                if let backgroundNode = backgroundGrid[r][c] as? SKSpriteNode {
                    // Stop animations for background nodes
                    backgroundNode.removeAllActions()
                    backgroundNode.children.forEach { $0.removeFromParent() } // Remove any child nodes
                    backgroundNode.size = CGSize(width: tileSideLength, height: tileSideLength) // Reset to default size
                }
                
                if let tileNode = tileMatrix[r][c] as? SKSpriteNode {
                    // Stop animations for tile nodes
                    tileNode.removeAllActions()
                    tileNode.setScale(1.0)
                    // Restore the original size, or reset to tileSideLength
                    if let originalSize = tileNode.userData?["originalSize"] as? CGSize {
                        tileNode.size = originalSize
                    } else {
                        tileNode.size = CGSize(width: tileSideLength, height: tileSideLength)
                    }
                    
                    // Remove child nodes (like glowing effects) if they exist
                    tileNode.children.forEach { $0.removeFromParent() }
                }
            }
        }
    }

    func reinitializePowerUp() {
        print("Reinitializing power-up...")

        // Reset power-up-related flags
        powerUpActive = false
        updatePowerup = false

        // Remove any existing power-up node
        powerUpNode.removeFromParent()

        // Restore specific power-up type and behaviors
        switch powerUpType {
        case "XPowerup":
            print("Reinitializing XPowerup.")
            powerUpNode = SKSpriteNode(imageNamed: "CS_delete_powerup")
        case "2xPowerup":
            print("Reinitializing 2xPowerup.")
            powerUpNode = SKSpriteNode(imageNamed: "CS_2xPowerup")
        case "TileAddPowerup":
            print("Reinitializing TileAddPowerup.")
            updatePowerup = true
            powerUpNode = SKSpriteNode(imageNamed: "CS_place_tile" + String(maxValue() / 4))
        default:
            print("No active power-up to reinitialize.")
            return // Exit early if no valid power-up type
        }

        // Set power-up node properties
        powerUpNode.size = CGSize(width: size.width / 5, height: size.width / 5)
        powerUpNode.position = calculatePowerupPosition()
        powerUpNode.zPosition = 100
        addChild(powerUpNode)
        powerUpNode.isHidden = false
        let glow = SKShapeNode(rectOf: CGSize(width: 65, height: 65), cornerRadius: 10)
        glow.strokeColor = .white
        glow.lineWidth = 2.0
        glow.glowWidth = 3.0
        glow.zPosition = powerUpNode.zPosition + 1
        glow.alpha = 0
        powerUpNode.addChild(glow)
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 1)
        let fadeIn = SKAction.fadeAlpha(to: 0.3, duration: 1)
        let pulse = SKAction.sequence([fadeIn, fadeOut])
        glow.run(SKAction.repeatForever(pulse))


        // Ensure all tiles and UI are in the correct state
        for row in 0..<rows {
            for col in 0..<columns {
                if let tileNode = tileMatrix[row][col] as? SKSpriteNode {
                    tileNode.alpha = 1.0 // Reset opacity
                    tileNode.removeAllActions() // Remove animations
                }

                if let backgroundNode = backgroundGrid[row][col] as? SKSpriteNode {
                    backgroundNode.removeAllActions()
                    backgroundNode.children.forEach { $0.removeFromParent() } // Remove glowing effects
                }
            }
        }

        print("Power-up successfully reinitialized.")
    }

    func calculateLosePosition() -> CGPoint {
        //iphone promax
        if UIScreen.main.bounds.width > 420 {
            return CGPoint(x: 0, y: size.height+43)
        }
        //iphone se
        else if UIScreen.main.bounds.width < 380 {
            return CGPoint(x: 0, y: size.height + 8)
        }
        //regular iphone
        else{
            return CGPoint(x: 0, y: size.height+12)
        }
    }
    
    func handleTouch(at location: CGPoint) {

        if let cancelButton = cancelButton, cancelButton.contains(location) {
            powerUpNode.isHidden = false
            progressBar.isHidden = false
            progressBarBackground.isHidden = false
            // Stop all animations and restore tile appearances
            for row in 0..<rows {
                for col in 0..<columns {
                    if let tileNode = tileMatrix[row][col] as? SKSpriteNode {
                        tileNode.removeAllActions() // Stop animations
                        tileNode.alpha = 1.0 // Restore full opacity
                        tileNode.setScale(1.0)

                        // Reset size if modified during animations
                        if let originalSize = tileNode.userData?["originalSize"] as? CGSize {
                            tileNode.size = originalSize
                        }
                    }

                    if let backgroundNode = backgroundGrid[row][col] as? SKSpriteNode {
                        backgroundNode.texture = getTextureForValue(0)
                        backgroundNode.removeAllActions() // Stop background animations
                        backgroundNode.children.forEach { $0.removeFromParent() } // Remove glowing effects
                        backgroundNode.size = CGSize(width: tileSideLength, height: tileSideLength) // Reset size
                    }
                }
            }

            // Remove the cancel button
            cancelButton.removeFromParent()
            self.cancelButton = nil

            // Reset progress bar visibility
            updateProgressBar() // Update the progress bar to reflect its pre-power-up state

            // Reinitialize power-up logic
            reinitializePowerUp()

            print("Power-up reinitialized. Ready for reuse.")
            return
        }



        // Check if the touch hit the power-up node
        if powerUpNode.contains(location) && powerUpNode.parent != nil {
            playPowerupSound()
            print("powerup sound play")
            activatePowerUp()
            return
        }

        // Handle tile interactions for power-ups
        for row in 0..<rows {
            for col in 0..<columns {
                guard let tileNode = backgroundGrid[row][col] as? SKSpriteNode else { continue }
                tileNode.setScale(1.0)

                // Check if the touch intersects the tile's frame
                if tileNode.frame.contains(location) {
                    let value = gameBoardMatrix[row][col]

                    // Handle XPowerup
                    if powerUpType == "XPowerup" && powerUpActive {
                        if value < maxValue() / 2 && value > 0 {
                            print("Removing tile at (\(row), \(col)) with value \(value)")
                            deactivatePowerUp()
                            playDeleteSound()
                            removeTile(atRow: row, column: col)
                        } else {
                            print("Cannot remove the highest-value tile!")
                        }
                        return
                    }

                    // Handle 2xPowerup
                    if powerUpType == "2xPowerup" && powerUpActive {
                        if value < maxValue() / 2 && value > 0 {
                            tileNode.alpha = 1.0 // Restore full opacity
                            tileNode.removeAllActions()
                            print("Doubled tile at (\(row), \(col)) to \(gameBoardMatrix[row][col])")
                            deactivatePowerUp()
                            playUpgradeSound()
                            upgradeTile(atRow: row, column: col)
                        } else {
                            print("Cannot double the highest-value tile!")
                        }
                        return
                    }

                    // Handle TileAddPowerup
                    if powerUpType == "TileAddPowerup" && powerUpActive {
                        if value == 0 {
                            let newTileValue = maxValue() / 4
                            gameBoardMatrix[row][col] = newTileValue
                            tileMatrix[row][col] = SKSpriteNode(texture: getTextureForValue(newTileValue))
                            (tileMatrix[row][col] as! SKSpriteNode).position = calculateTilePosition(row: row, col: col)
                            (tileMatrix[row][col] as! SKSpriteNode).size = CGSize(width: tileSideLength, height: tileSideLength)
                            (tileMatrix[row][col] as! SKSpriteNode).setScale(0.0)
                            addChild(tileMatrix[row][col] as! SKSpriteNode)
                            
                            let scaleUp = SKAction.scale(to: 1.0, duration: 0.3) // Smooth scale-up animation
                            scaleUp.timingMode = .easeOut
                            (tileMatrix[row][col] as! SKSpriteNode).run(scaleUp)
                            
                            playPlaceSound() 
                            print("Added tile at (\(row), \(col)) with value \(newTileValue)")
                            updatePowerup = false
                            for r in 0...3 {
                                for c in 0...3 {
                                    (backgroundGrid[r][c] as! SKSpriteNode).texture = getTextureForValue(0)
                                    (backgroundGrid[r][c] as! SKSpriteNode).alpha = 1.0
                                    (backgroundGrid[r][c] as! SKSpriteNode).removeAllChildren()
                                }
                            }
                            delay(0.3) {self.deactivatePowerUp()}
                        } else {
                            print("Invalid location! Tap an empty space to place the new tile.")
                        }
                        return
                    }
                }
            }
        }
    }

    func dimAllTiles() {
        for row in 0..<rows {
            for col in 0..<columns {
                guard let tileNode = tileMatrix[row][col] as? SKSpriteNode else { continue }
                
                // Fade to 30% opacity over 3 seconds
                let fadeToAlpha = SKAction.fadeAlpha(to: 0.3, duration: 1.5)
                tileNode.run(fadeToAlpha)
            }
        }
    }









    func setupProgressBar() {
        // Create the background asset
        let assetTexture = SKTexture(imageNamed: "CS_powerup_base")
        progressBarBackground = SKSpriteNode(texture: assetTexture, size: CGSize(width: size.width / 5, height: size.width / 5)) // A square size
        progressBarBackground.position = calculatePowerupPosition()
        progressBarBackground.zPosition = 10
        addChild(progressBarBackground)
        
        // Create the progress bar, initially covering the entire background
        progressBar = SKSpriteNode(color: .black, size: CGSize(width: progressBarBackground.size.width, height: progressBarBackground.size.height)) // Start full size
        progressBar.anchorPoint = CGPoint(x: 0.5, y: 1.0) // Anchor at the top-center
        progressBar.position = CGPoint(x: 0, y: progressBarBackground.size.height / 2) // Top of progressBar aligns with top of background
        progressBar.alpha = 0.7 // Slightly opaque for visual effect
        progressBar.zPosition = 11
        progressBarBackground.addChild(progressBar)
    }


    func delay(_ seconds: Double, execute: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: execute)
    }

    
    func updateProgressBar() {
        let progress = min(CGFloat(powerUpScore) / CGFloat(powerUpMultiplier), 1.0) // Clamp progress to a max of 1.0
        let newHeight = progressBarBackground.size.height * (1.0 - progress) // Calculate the remaining height of the black bar
        
        // Animate the height change while keeping the top anchored
        let resizeAction = SKAction.resize(toHeight: newHeight, duration: 0.3) // Adjust duration as needed
        progressBar.run(resizeAction)
    }



}

