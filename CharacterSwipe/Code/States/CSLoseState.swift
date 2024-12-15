import GameplayKit
import SpriteKit

class CSLoseState: CSGameState {
    
    private var rectangleBackgroundEnd: SKShapeNode! // Make this a property to access it later
    var gameBoard: CSGameBoard!
    
    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        
        // Schedule the create_lose_board() to run after 5 seconds
        runAfterDelay(2.0) { [weak self] in
            create_lose_board()
        }
    
    
    // Function to run a closure after a delay
    func runAfterDelay(_ delay: TimeInterval, block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
    
        func create_lose_board() {
            gameBoard = gameScene.getGameBoard()
            
            // Create the rectangle background
            rectangleBackgroundEnd = SKShapeNode(rectOf: CGSize(width: 320, height: 500), cornerRadius: 20)
            rectangleBackgroundEnd.fillColor = SKColor(red: 28/255, green: 28/255, blue: 28/255, alpha: 1)
            rectangleBackgroundEnd.strokeColor = SKColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1)
            rectangleBackgroundEnd.lineWidth = 3 // Border thickness
            rectangleBackgroundEnd.position = CGPoint(x: gameScene.size.width / 2, y: gameScene.size.height / 2)
            rectangleBackgroundEnd.zPosition = 100 // Ensure it's above other nodes
            rectangleBackgroundEnd.setScale(0.0) // Start at scale 0 for animation

            // Add rectangle to the scene
            gameScene.addChild(rectangleBackgroundEnd)
            
            // Create the restart button
            let restartButton = SKShapeNode(rectOf: CGSize(width: 200, height: 50), cornerRadius: 10) // Rounded corners
            restartButton.fillColor = .red
            restartButton.strokeColor = SKColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1) // Gray outline
            restartButton.lineWidth = 3 // Stroke width
            restartButton.position = CGPoint(x: 0, y: 0) // Centered relative to rectangleBackgroundEnd
            restartButton.name = "restartButton" // Set a name for the button
            restartButton.zPosition = 101
            
            // Create the restart label
            let restartLabel = SKLabelNode(text: "Restart Game")
            restartLabel.fontColor = .white
            restartLabel.fontSize = 24
            restartLabel.verticalAlignmentMode = .center // Center text vertically
            restartLabel.horizontalAlignmentMode = .center // Center text horizontally
            restartLabel.position = CGPoint(x: 0, y: 0) // Centered relative to restartButton
            restartButton.addChild(restartLabel)
            
            // Add the restart button to the rectangle
            rectangleBackgroundEnd.addChild(restartButton)
            
            // Animate the pop effect
            let scaleUp = SKAction.scale(to: 1.2, duration: 0.15)
            let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
            let popAnimation = SKAction.sequence([scaleUp, scaleDown])
            rectangleBackgroundEnd.run(popAnimation)
            
            print("Lose state entered: Displaying Restart Button with blur")
        }

    }
    func startGame() {
        print("Restart button tapped, transitioning to gameplay state")
        stateMachine?.enter(CSGameplayState.self)
        rectangleBackgroundEnd.removeFromParent()
    }
    
    func handleTouch(at location: CGPoint) {
        let convertedLocation = rectangleBackgroundEnd.convert(location, from: gameScene)

        if let restartButton = rectangleBackgroundEnd.childNode(withName: "restartButton"),
           restartButton.contains(convertedLocation) {
            print("Restart button tapped")
            startGame()
            gameBoard.initializeBoardValues()
            gameBoard.setupGrid()
            gameScene.updateTiles()
        } else {
            print("Touched outside of restart button")
        }
    }

}
