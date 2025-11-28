


import SwiftUI
import Combine

// MARK: - Game Models
struct Player {
    var position: Int // 0: left, 1: center, 2: right
    var isJumping: Bool = false
    var isSliding: Bool = false
    var yOffset: CGFloat = 0
}

struct Obstacle: Identifiable {
    let id = UUID()
    var position: Int // 0, 1, 2
    var type: ObstacleType
    var distance: CGFloat // Distance from player
}

enum ObstacleType {
    case rock, lowCeiling, gap, crystal
}

struct GameState {
    var score: Int = 0
    var distance: CGFloat = 0
    var speed: CGFloat = 8
    var isGameActive: Bool = false
    var isGameOver: Bool = false
    var currentLevel: Int = 1
    var showLevelComplete: Bool = false
    var completedLevel: Int = 0
}

struct ScoreRecord: Identifiable, Codable {
    var id = UUID()
    let score: Int
    let date: Date
    let level: Int
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Game Manager
class LostMineGameManager: ObservableObject {
    @Published var player = Player(position: 1)
    @Published var obstacles: [Obstacle] = []
    @Published var gameState = GameState()
    @Published var scoreRecords: [ScoreRecord] = []
    
    private var gameTimer: Timer?
    private var levelCompleteTimer: Timer?
    private let trackCount = 3
    private let obstacleSpacing: CGFloat = 400
    private var lastObstacleDistance: CGFloat = 800
    private var previousLevel: Int = 1
    
    init() {
        loadScoreRecords()
    }
    
    func startGame() {
        resetGame()
        gameState.isGameActive = true
        
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, self.gameState.isGameActive else { return }
            self.updateGame()
        }
    }
    
    func pauseGame() {
        gameState.isGameActive = false
        gameTimer?.invalidate()
        gameTimer = nil
    }
    
    func resumeGame() {
        guard !gameState.isGameActive else { return }
        gameState.isGameActive = true
        
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, self.gameState.isGameActive else { return }
            self.updateGame()
        }
    }
    
    func resetGame() {
        player = Player(position: 1)
        obstacles.removeAll()
        gameState = GameState()
        lastObstacleDistance = 800
        previousLevel = 1
        
        // Create initial obstacles
        generateInitialObstacles()
    }
    
    private func generateInitialObstacles() {
        for i in 0..<10 {
            let obstacleType: ObstacleType = [.rock, .lowCeiling, .gap, .crystal].randomElement()!
            let position = Int.random(in: 0..<trackCount)
            let distance = lastObstacleDistance + CGFloat(i) * obstacleSpacing
            obstacles.append(Obstacle(position: position, type: obstacleType, distance: distance))
        }
        lastObstacleDistance += CGFloat(10) * obstacleSpacing
    }
    
    private func updateGame() {
        guard gameState.isGameActive else { return }
        
        // Update game state
        gameState.distance += gameState.speed
        gameState.score = Int(gameState.distance / 10)
        
        // Update level and check for level completion
        let newLevel = min(gameState.score / 1000 + 1, 10)
        if newLevel != gameState.currentLevel {
            gameState.currentLevel = newLevel
            showLevelComplete()
        }
        
        // Move obstacles toward player
        updateObstacles()
        
        // Generate new obstacles
        if lastObstacleDistance < gameState.distance + 2000 {
            generateObstacle()
        }
        
        // Check collisions
        checkCollisions()
    }
    
    private func showLevelComplete() {
        guard !gameState.showLevelComplete else { return }
        
        gameState.showLevelComplete = true
        gameState.completedLevel = gameState.currentLevel - 1
        gameState.isGameActive = false
        
        // Stop the game timer
        gameTimer?.invalidate()
        gameTimer = nil
        
        // Set timer to hide level complete view after 3 seconds
        levelCompleteTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.hideLevelComplete()
        }
    }
    
    private func hideLevelComplete() {
        gameState.showLevelComplete = false
        gameState.isGameActive = true
        
        // Resume game
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, self.gameState.isGameActive else { return }
            self.updateGame()
        }
        
        levelCompleteTimer?.invalidate()
        levelCompleteTimer = nil
    }
    
    private func updateObstacles() {
        obstacles = obstacles.map { obstacle in
            var updatedObstacle = obstacle
            updatedObstacle.distance -= gameState.speed
            return updatedObstacle
        }.filter { $0.distance > -200 }
    }
    
    private func generateObstacle() {
        let obstacleType: ObstacleType = [.rock, .lowCeiling, .gap, .crystal].randomElement()!
        let position = Int.random(in: 0..<trackCount)
        let obstacle = Obstacle(position: position, type: obstacleType, distance: lastObstacleDistance)
        
        obstacles.append(obstacle)
        lastObstacleDistance += obstacleSpacing
    }
    
    private func checkCollisions() {
        for obstacle in obstacles {
            // Check if obstacle is in collision range (50-150 units away)
            if obstacle.distance < 150 && obstacle.distance > 50 {
                if obstacle.position == player.position {
                    handleCollision(with: obstacle)
                    break
                }
            }
        }
    }
    
    private func handleCollision(with obstacle: Obstacle) {
        switch obstacle.type {
        case .rock:
            if !player.isJumping {
                endGame()
            }
        case .lowCeiling:
            if !player.isSliding {
                endGame()
            }
        case .gap:
            if !player.isJumping {
                endGame()
            }
        case .crystal:
            // Collect crystal - remove it and add points
            if let index = obstacles.firstIndex(where: { $0.id == obstacle.id }) {
                obstacles.remove(at: index)
                gameState.score += 100
            }
        }
    }
    
    func moveLeft() {
        guard gameState.isGameActive else { return }
        player.position = max(0, player.position - 1)
    }
    
    func moveRight() {
        guard gameState.isGameActive else { return }
        player.position = min(2, player.position + 1)
    }
    
    func jump() {
        guard gameState.isGameActive && !player.isJumping && !player.isSliding else { return }
        
        player.isJumping = true
        withAnimation(.easeOut(duration: 0.3)) {
            player.yOffset = -80
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.3)) {
                self.player.yOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.player.isJumping = false
            }
        }
    }
    
    func slide() {
        guard gameState.isGameActive && !player.isJumping && !player.isSliding else { return }
        
        player.isSliding = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.player.isSliding = false
        }
    }
    
    func endGame() {
        gameState.isGameActive = false
        gameState.isGameOver = true
        gameTimer?.invalidate()
        gameTimer = nil
        levelCompleteTimer?.invalidate()
        levelCompleteTimer = nil
        
        // Save score
        let record = ScoreRecord(score: gameState.score, date: Date(), level: gameState.currentLevel)
        scoreRecords.append(record)
        saveScoreRecords()
    }
    
    // MARK: - Score Management
    private func saveScoreRecords() {
        if let encoded = try? JSONEncoder().encode(scoreRecords) {
            UserDefaults.standard.set(encoded, forKey: "lostMineScoreRecords")
        }
    }
    
    private func loadScoreRecords() {
        if let data = UserDefaults.standard.data(forKey: "lostMineScoreRecords"),
           let decoded = try? JSONDecoder().decode([ScoreRecord].self, from: data) {
            scoreRecords = decoded.sorted { $0.score > $1.score }
        }
    }
    
    func clearScoreRecords() {
        scoreRecords.removeAll()
        UserDefaults.standard.removeObject(forKey: "lostMineScoreRecords")
    }
}

// MARK: - Level Complete View
struct LevelCompleteView: View {
    let level: Int
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            // Level complete card
            VStack(spacing: 25) {
                // Trophy icon
                Image(systemName: "trophy.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.yellow)
                    .scaleEffect(scale)
                
                // Level text
                VStack(spacing: 10) {
                    Text("LEVEL COMPLETE!")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: .black, radius: 5)
                    
                    Text("Level \(level)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 3)
                }
                
                // Congratulations text
                Text("Congratulations! Keep going!")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                
                // Progress indicator
                HStack(spacing: 5) {
                    ForEach(1...10, id: \.self) { i in
                        Circle()
                            .fill(i <= level ? Color.yellow : Color.gray.opacity(0.5))
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.9),
                                Color.purple.opacity(0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            )
            .padding(40)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

// MARK: - Splash Screen
struct SplashScreenView: View {
    @State private var animationProgress: CGFloat = 0
    @State private var showGame = false
    @State private var titleScale: CGFloat = 0.8
    @State private var subtitleOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Dark cave background
            GeometryReader { geometry in
                Image("game_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            // Animated tracks/lanes
            VStack(spacing: 60) {
                ForEach(0..<3, id: \.self) { index in
                    AnimatedTrackView(animationProgress: animationProgress, delay: Double(index) * 0.2)
                }
            }
            
            // Title and content
            VStack(spacing: 30) {
                Spacer()
                
                // Main Title
                VStack(spacing: 10) {
                    Text("LostMine")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                        .shadow(color: .black, radius: 10)
                        .scaleEffect(titleScale)
                    
                    Text("RailRider")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: .black, radius: 8)
                        .scaleEffect(titleScale)
                }
                
                // Subtitle
                Text("Underground Adventure")
                    .font(.title2)
                    .foregroundColor(.white)
                    .opacity(subtitleOpacity)
                
                Spacer()
                
                // Start Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showGame = true
                    }
                }) {
                    Text("START JOURNEY")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 250, height: 60)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .red]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(30)
                        .shadow(color: .orange, radius: 20)
                        .scaleEffect(subtitleOpacity)
                }
                .opacity(subtitleOpacity)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            // Start track animation
            withAnimation(.easeOut(duration: 2.0)) {
                animationProgress = 1.0
            }
            
            // Title animation
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.5)) {
                titleScale = 1.0
            }
            
            // Subtitle and button animation
            withAnimation(.easeIn(duration: 0.8).delay(1.2)) {
                subtitleOpacity = 1.0
            }
        }
        .fullScreenCover(isPresented: $showGame) {
          
            MainMenuView()
        }
    }
}

struct AnimatedTrackView: View {
    let animationProgress: CGFloat
    let delay: Double
    @State private var glowOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Track with moving lines
            ZStack {
                // Background glow
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.yellow.opacity(0.3))
                    .frame(width: 80, height: 8)
                    .opacity(glowOpacity)
                
                // Moving track lines
                ForEach(0..<15, id: \.self) { i in
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 40, height: 3)
                        .offset(x: -200 + (animationProgress * 400) + (CGFloat(i) * 30))
                        .opacity(0.6 + (sin(CGFloat(i) * 0.5) * 0.4))
                }
            }
            .frame(width: 200, height: 10)
        }
        .onAppear {
            // Glow animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay)) {
                glowOpacity = 1.0
            }
        }
    }
}

// MARK: - Main Game View
struct LostMineGameView: View {
    @StateObject private var gameManager = LostMineGameManager()
    @Environment(\.dismiss) private var dismiss
    @State private var showPauseMenu = false
    
    var body: some View {
        ZStack {
            // Background
           // GameBackgroundView()
            
            GeometryReader { geometry in
                Image("game_background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                GameHeaderView(gameManager: gameManager, showPauseMenu: $showPauseMenu)
                    .padding(.top, 30)
                    .padding(.horizontal)
                
                Spacer()
                
                // Game Area
                GameAreaView(gameManager: gameManager)
                    .frame(height: 400)
                
                Spacer()
                
                // Controls
                GameControlsView(gameManager: gameManager)
                    .padding(.bottom, 30)
                    .padding(.horizontal)
            }
            
            // Overlays
            if gameManager.gameState.isGameOver {
                GameOverView(gameManager: gameManager, dismiss: dismiss)
            }
            
            if showPauseMenu {
                PauseMenuView(gameManager: gameManager, showPauseMenu: $showPauseMenu, dismiss: dismiss)
            }
            
            // Level Complete Overlay
            if gameManager.gameState.showLevelComplete {
                LevelCompleteView(level: gameManager.gameState.completedLevel)
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            gameManager.startGame()
        }
        .onChange(of: showPauseMenu) { oldIsShowing,isShowing in
            if isShowing {
                gameManager.pauseGame()
            }
        }
    }
}

// MARK: - Game Header
struct GameHeaderView: View {
    @ObservedObject var gameManager: LostMineGameManager
    @Binding var showPauseMenu: Bool
    
    var body: some View {
        HStack {
            // Pause Button
            Button(action: {
                showPauseMenu = true
                gameManager.pauseGame()
            }) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Score and Level
            VStack(spacing: 4) {
                Text("\(gameManager.gameState.score)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 3)
                
                Text("Level \(gameManager.gameState.currentLevel)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
            }
            
            Spacer()
            
            // Restart Button (only visible when game not active)
            Button(action: { gameManager.startGame() }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
            .opacity(gameManager.gameState.isGameActive ? 0 : 1)
        }
    }
}

// MARK: - Game Area
struct GameAreaView: View {
    @ObservedObject var gameManager: LostMineGameManager
    
    var body: some View {
        ZStack {
            // Tracks
            HStack(spacing: 80) {
                ForEach(0..<3, id: \.self) { index in
                    TrackView(isActive: gameManager.player.position == index)
                }
            }
            
            // Obstacles
            ForEach(gameManager.obstacles) { obstacle in
                ObstacleView(obstacle: obstacle, distance: obstacle.distance)
            }
            
            // Player
            PlayerView(player: gameManager.player)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TrackView: View {
    let isActive: Bool
    
    var body: some View {
        ZStack {
            // Track lines
            ForEach(0..<20, id: \.self) { i in
                Rectangle()
                    .fill(isActive ? Color.yellow : Color.gray.opacity(0.5))
                    .frame(height: 2)
                    .offset(y: CGFloat(i) * 20 - 200)
            }
            
            // Glow effect for active track
            if isActive {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.yellow.opacity(0.3))
                    .frame(width: 60, height: 400)
                    .blur(radius: 10)
            }
        }
        .frame(width: 60)
    }
}

struct ObstacleView: View {
    let obstacle: Obstacle
    let distance: CGFloat
    
    var body: some View {
        HStack(spacing: 80) {
            ForEach(0..<3, id: \.self) { position in
                if obstacle.position == position {
                    obstacleContent
                        .offset(y: -distance + 200) // Adjust based on distance
                } else {
                    Color.clear
                        .frame(width: 60, height: 60)
                }
            }
        }
    }
    
    @ViewBuilder
    private var obstacleContent: some View {
        switch obstacle.type {
        case .rock:
            RockView()
        case .lowCeiling:
            LowCeilingView()
        case .gap:
            GapView()
        case .crystal:
            CrystalView()
        }
    }
}

struct RockView: View {
    var body: some View {
        Circle()
            .fill(Color.gray)
            .frame(width: 50, height: 50)
            .overlay(
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 25, height: 25)
            )
            .shadow(color: .black, radius: 5)
    }
}

struct LowCeilingView: View {
    var body: some View {
        Rectangle()
            .fill(Color.brown)
            .frame(width: 80, height: 25)
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(height: 8)
            )
            .cornerRadius(5)
    }
}

struct GapView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.red.opacity(0.8))
            .frame(width: 70, height: 40)
            .overlay(
                Text("GAP")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white)
            )
    }
}

struct CrystalView: View {
    @State private var glow = false
    
    var body: some View {
        Diamond()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple, .cyan]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 35, height: 45)
            .overlay(
                Diamond()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .blue, radius: glow ? 15 : 5)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    glow.toggle()
                }
            }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct PlayerView: View {
    let player: Player
    
    var body: some View {
        HStack(spacing: 80) {
            ForEach(0..<3, id: \.self) { position in
                if player.position == position {
                    MineCartView(
                        isJumping: player.isJumping,
                        isSliding: player.isSliding,
                        yOffset: player.yOffset
                    )
                } else {
                    Color.clear
                        .frame(width: 80, height: 80)
                }
            }
        }
    }
}

struct MineCartView: View {
    let isJumping: Bool
    let isSliding: Bool
    let yOffset: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            // Mine Cart
            ZStack {
                // Cart body
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .red, .brown]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: isSliding ? 25 : 35)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black, lineWidth: 3)
                    )
                
                // Wheels
                HStack(spacing: 30) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 15, height: 15)
                    
                    Circle()
                        .fill(Color.black)
                        .frame(width: 15, height: 15)
                }
                .offset(y: 10)
            }
            .offset(y: yOffset + (isJumping ? -50 : 0))
            
            // Glow effect
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.4))
                .frame(width: 80, height: isSliding ? 35 : 45)
                .blur(radius: 15)
                .offset(y: yOffset + (isJumping ? -50 : 0))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isJumping)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSliding)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: yOffset)
    }
}

// MARK: - Game Controls
struct GameControlsView: View {
    @ObservedObject var gameManager: LostMineGameManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Jump Button
            Button(action: { gameManager.jump() }) {
                ControlButton(systemName: "arrow.up", color: .green, text: "JUMP")
            }
            
            // Movement Buttons
            HStack(spacing: 20) {
                Button(action: { gameManager.moveLeft() }) {
                    ControlButton(systemName: "arrow.left", color: .blue, text: "LEFT")
                }
                
                Button(action: { gameManager.moveRight() }) {
                    ControlButton(systemName: "arrow.right", color: .blue, text: "RIGHT")
                }
            }
            
            // Slide Button
            Button(action: { gameManager.slide() }) {
                ControlButton(systemName: "arrow.down", color: .orange, text: "SLIDE")
            }
        }
    }
}

struct ControlButton: View {
    let systemName: String
    let color: Color
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundColor(.white)
            
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 70, height: 70)
        .background(color)
        .clipShape(Circle())
        .shadow(color: color.opacity(0.5), radius: 10, y: 5)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Background
struct GameBackgroundView: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Dark cave background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Animated cave texture
            ForEach(0..<15, id: \.self) { i in
                CaveTexture(offset: animationOffset + CGFloat(i) * 30)
            }
            
            // Floating particles
            ForEach(0..<20, id: \.self) { i in
                DustParticle(index: i)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                animationOffset = -100
            }
        }
    }
}

struct CaveTexture: View {
    let offset: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.brown.opacity(0.2),
                        Color.gray.opacity(0.1),
                        Color.brown.opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 30, height: 150)
            .offset(x: offset)
            .blur(radius: 1)
    }
}

struct DustParticle: View {
    let index: Int
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: CGFloat.random(in: 1...4))
            .position(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
            )
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 2...4))
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = Double.random(in: 0.1...0.3)
                    xOffset = CGFloat.random(in: -20...20)
                    yOffset = CGFloat.random(in: -10...10)
                }
            }
    }
}

// MARK: - Game Over View
struct GameOverView: View {
    @ObservedObject var gameManager: LostMineGameManager
    let dismiss: DismissAction
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("GAME OVER")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                    .shadow(color: .black, radius: 5)
                
                VStack(spacing: 20) {
                    Text("Final Score")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    Text("\(gameManager.gameState.score)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                    
                    Text("Level \(gameManager.gameState.currentLevel)")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                
                VStack(spacing: 15) {
                    Button("Play Again") {
                        gameManager.startGame()
                    }
                    .gameButtonStyle(color: .green)
                    
                    Button("Main Menu") {
                        dismiss()
                    }
                    .gameButtonStyle(color: .blue)
                }
                .frame(width: 250)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.systemGray6))
                    .shadow(radius: 20)
            )
            .padding(40)
        }
    }
}

// MARK: - Pause Menu
struct PauseMenuView: View {
    @ObservedObject var gameManager: LostMineGameManager
    @Binding var showPauseMenu: Bool
    let dismiss: DismissAction
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("PAUSED")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                
                VStack(spacing: 8) {
                    Text("Score: \(gameManager.gameState.score)")
                    Text("Level: \(gameManager.gameState.currentLevel)")
                    Text("Distance: \(Int(gameManager.gameState.distance))m")
                }
                .foregroundColor(.green)
                .font(.system(size: 18, weight: .medium))
                
                VStack(spacing: 15) {
                    Button("Resume") {
                        showPauseMenu = false
                        gameManager.resumeGame()
                    }
                    .gameButtonStyle(color: .green)
                    
                    Button("Restart") {
                        showPauseMenu = false
                        gameManager.startGame()
                    }
                    .gameButtonStyle(color: .orange)
                    
                    Button("Main Menu") {
                        dismiss()
                    }
                    .gameButtonStyle(color: .blue)
                }
                .frame(width: 250)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color(.systemGray6))
                    .shadow(radius: 20)
            )
            .padding(40)
        }
    }
}

// MARK: - Button Style Extension
extension View {
    func gameButtonStyle(color: Color) -> some View {
        self
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .cornerRadius(15)
            .shadow(color: color.opacity(0.5), radius: 10, y: 5)
    }
}

// MARK: - Scores View

struct ScoresView: View {
    @StateObject private var gameManager = LostMineGameManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                GeometryReader { geometry in
                    Image("game_background")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .ignoresSafeArea()
                }
                .ignoresSafeArea()
                
                VStack {
                    Text("HIGH SCORES")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.top, 30)
                    
                    if gameManager.scoreRecords.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Text("No scores yet!")
                                .foregroundColor(.white)
                                .font(.title2)
                            Text("Play the game to set some records!")
                                .foregroundColor(.gray)
                                .font(.body)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(Array(gameManager.scoreRecords.prefix(10).enumerated()), id: \.element.id) { index, record in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(record.score) points")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        Text("Level \(record.level) • \(record.formattedDate)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("#\(index + 1)")
                                        .font(.system(size: 16, weight: .black))
                                        .foregroundColor(.yellow)
                                }
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                    
                    Button("Clear Scores") {
                        gameManager.clearScoreRecords()
                    }
                    .gameButtonStyle(color: .red)
                    .padding()
                }
            }
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

// MARK: - How to Play View
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color.black
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Header
                        VStack(spacing: 8) {
                            Text("LEARN TO PLAY")
                                .font(.system(size: 33, weight: .black, design: .rounded))
                                .foregroundColor(.orange)
                            
                            Text("Master the LostMine RailRider")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 20)
                        
                        // Game Objective
                        GameInstructionCard(
                            title: "🎯 Game Objective",
                            description: "Navigate your Ore Cart through the underground tracks for as long as possible while collecting crystals and avoiding obstacles.",
                            color: .blue
                        )
                        
                        // Controls Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("🎮 Controls")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            ControlInstructionRow(
                                icon: "arrow.left",
                                title: "Move Left",
                                description: "Switch to left track",
                                color: .blue
                            )
                            
                            ControlInstructionRow(
                                icon: "arrow.right",
                                title: "Move Right",
                                description: "Switch to right track",
                                color: .blue
                            )
                            
                            ControlInstructionRow(
                                icon: "arrow.up",
                                title: "Jump",
                                description: "Jump over rocks and gaps",
                                color: .green
                            )
                            
                            ControlInstructionRow(
                                icon: "arrow.down",
                                title: "Slide",
                                description: "Duck under low ceilings",
                                color: .orange
                            )
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Obstacles Section
                        VStack(alignment: .leading, spacing: 15) {
                            Text("🚧 Obstacles & Items")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            ObstacleInstructionRow(
                                obstacle: ObstacleType.rock,
                                title: "Rock",
                                description: "Jump over it using UP arrow",
                                action: "Jump"
                            )
                            
                            ObstacleInstructionRow(
                                obstacle: ObstacleType.lowCeiling,
                                title: "Low Ceiling",
                                description: "Slide under it using DOWN arrow",
                                action: "Slide"
                            )
                            
                            ObstacleInstructionRow(
                                obstacle: ObstacleType.gap,
                                title: "Gap",
                                description: "Jump over the chasm",
                                action: "Jump"
                            )
                            
                            ObstacleInstructionRow(
                                obstacle: ObstacleType.crystal,
                                title: "Crystal",
                                description: "Collect for +100 points",
                                action: "Just pass through"
                            )
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Game Rules
                        VStack(alignment: .leading, spacing: 15) {
                            Text("📜 Game Rules")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            RuleRow(
                                icon: "❌",
                                title: "Game Over When:",
                                description: "You hit a rock without jumping\nYou hit a low ceiling without sliding\nYou fall into a gap without jumping"
                            )
                            
                            RuleRow(
                                icon: "📈",
                                title: "Level Progression:",
                                description: "Level increases every 1000 points\nSpeed increases with each level\nMaximum level: 10"
                            )
                            
                            RuleRow(
                                icon: "💎",
                                title: "Scoring:",
                                description: "1 point per 10 units distance\n+100 points for each crystal collected\nHigher levels = faster score accumulation"
                            )
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Tips Section
                        GameInstructionCard(
                            title: "💡 Pro Tips",
                            description: "• Always look ahead to plan your moves\n• Time your jumps and slides carefully\n• Collect crystals for bonus points\n• The game gets faster as you progress\n• Practice switching lanes smoothly",
                            color: .purple
                        )
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Instruction Card Components
struct GameInstructionCard: View {
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            
            Text(description)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}

struct ControlInstructionRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 15) {
            // Icon
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
        }
    }
}

struct ObstacleInstructionRow: View {
    let obstacle: ObstacleType
    let title: String
    let description: String
    let action: String
    
    var body: some View {
        HStack(spacing: 15) {
            // Obstacle Preview
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 60, height: 60)
                
                Group {
                    switch obstacle {
                    case .rock:
                        RockView()
                    case .lowCeiling:
                        LowCeilingView()
                    case .gap:
                        GapView()
                    case .crystal:
                        CrystalView()
                    }
                }
                .scaleEffect(0.8)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Action
            Text(action)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
        }
    }
}

struct RuleRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(icon)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .lineSpacing(2)
            }
            
            Spacer()
        }
    }
}

// MARK: - Updated Main Menu with How to Play Button
struct MainMenuView: View {
    @State private var showGame = false
    @State private var showScores = false
    @State private var showHowToPlay = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
              
                
                GeometryReader { geometry in
                    Image("game_background")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.5)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .ignoresSafeArea()
                }
                .ignoresSafeArea()
                
                
                
                ScrollView{
                VStack(spacing: 40) {
                    // Title
                    VStack(spacing: 20) {
                        Text("LostMine\nRailRider")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundColor(.orange)
                            .shadow(color: .black, radius: 5)
                        
                        Text("Underground Adventure")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 60)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 20) {
                        Button("START GAME") {
                            showGame = true
                        }
                        .gameButtonStyle(color: .green)
                        .frame(width: 220)
                        
                        Button("HIGH SCORES") {
                            showScores = true
                        }
                        .gameButtonStyle(color: .blue)
                        .frame(width: 220)
                        
                        
                    }
                    
                    Spacer()
                    
                    // How to Play Button
                    Button(action: {
                        showHowToPlay = true
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                          
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.purple)
                        .cornerRadius(25)
                        .shadow(color: .purple.opacity(0.5), radius: 10, y: 5)
                    }
                    
                    // Features
                    VStack(spacing: 15) {
                        Text("GAME FEATURES")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.yellow)
                        
                        HStack(spacing: 15) {
                            FeatureTag(text: "3 TRACKS")
                            FeatureTag(text: "4 OBSTACLES")
                            FeatureTag(text: "JUMP & SLIDE")
                        }
                        
                        FeatureTag(text: "10 levels")
                    }
                    .padding(.bottom, 50)
                }
            }
            }
            .fullScreenCover(isPresented: $showGame) {
                LostMineGameView()
            }
            .sheet(isPresented: $showScores) {
                ScoresView()
            }
            .sheet(isPresented: $showHowToPlay) {
                HowToPlayView()
            }
        }
    }
}

// MARK: - Updated Feature Tag
struct FeatureTag: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.3))
            .cornerRadius(12)
    }
}
