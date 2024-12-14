import GameplayKit
import SpriteKit

class CSLoseState: CSGameState {
    
    private var overlayNode: SKSpriteNode?
    private var rectangleBackgroundEnd: SKShapeNode! // Make this a property to access it later
    var gameBoard: CSGameBoard!
    
    override func didEnter(from previousState: GKState?) {
        super.didEnter(from: previousState)
        gameBoard = gameScene.getGameBoard()
        
        // Create a semi-transparent dark overlay
//        let overlay = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: gameScene.size)
//        overlay.position = CGPoint(x: gameScene.size.width / 2, y: gameScene.size.height / 2)
//        overlay.zPosition = 100
//        overlay.isUserInteractionEnabled = false // Ensure overlay does not block touches
//        gameScene.addChild(overlay)
//        overlayNode = overlay
//        
//        // Apply blur effect using SKEffectNode
//        let blurEffect = SKEffectNode()
//        blurEffect.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 10])
//        blurEffect.shouldRasterize = true
//        
//        // Capture a snapshot of the game scene
//        if let texture = gameScene.view?.texture(from: gameScene) {
//            let snapshot = SKSpriteNode(texture: texture)
//            snapshot.size = gameScene.size
//            snapshot.anchorPoint = CGPoint(x: 0.5, y: 0.5)
//            snapshot.position = CGPoint(x: 0, y: 0) // Center inside blurEffect
//            blurEffect.addChild(snapshot)
//        }
//        
//        // Center the blur effect on the overlay
//        blurEffect.position = CGPoint(x: 0, y: 0)
//        overlay.addChild(blurEffect)
//        
//        // Create the rectangle background for the button
        rectangleBackgroundEnd = SKShapeNode(rectOf: CGSize(width: 320, height: 500), cornerRadius: 20)
        rectangleBackgroundEnd.fillColor = SKColor(red: 28/255, green: 28/255, blue: 28/255, alpha: 1)
        rectangleBackgroundEnd.strokeColor = SKColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1)
        rectangleBackgroundEnd.lineWidth = 3 // Border thickness
        rectangleBackgroundEnd.position = CGPoint(x: gameScene.size.width / 2, y: gameScene.size.height / 2)
        rectangleBackgroundEnd.zPosition = 100 // Ensure it's above other nodes
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
        
        print("Lose state entered: Displaying Restart Button with blur")
    }
    
    func startGame() {
        print("Restart button tapped, transitioning to gameplay state")
        stateMachine?.enter(CSGameplayState.self)
        overlayNode?.removeFromParent()
        
        // Remove rectangle background when restarting
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
