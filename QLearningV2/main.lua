-- main.lua (Phiên bản HOÀN CHỈNH - Q-learning + Inspector Mode)

-- Load configuration file safely
local success, Config = pcall(require, "config")
if not success then
    error("Could not load config.lua! Make sure it exists and has correct syntax.\nError: " .. tostring(Config))
end
-- Cung cấp giá trị mặc định
Config.maze = Config.maze or {}
Config.maze.width = Config.maze.width or 15
Config.maze.height = Config.maze.height or 10
Config.maze.cell_size = Config.maze.cell_size or 30
Config.maze.wall_thickness = Config.maze.wall_thickness or 2

Config.q_learning = Config.q_learning or {}
Config.q_learning.episodes = Config.q_learning.episodes or 5000
Config.q_learning.alpha = Config.q_learning.alpha or 0.1
Config.q_learning.gamma = Config.q_learning.gamma or 0.9
Config.q_learning.epsilon_start = Config.q_learning.epsilon_start or 1.0
Config.q_learning.epsilon_decay = Config.q_learning.epsilon_decay or 0.9995
Config.q_learning.epsilon_min = Config.q_learning.epsilon_min or 0.01
Config.q_learning.max_steps_per_episode_factor = Config.q_learning.max_steps_per_episode_factor or 2

Config.rewards = Config.rewards or {}
Config.rewards.goal = Config.rewards.goal or 100
Config.rewards.step = Config.rewards.step or -0.1

Config.visualization = Config.visualization or {}
Config.visualization.initial_speed = Config.visualization.initial_speed or 5
Config.visualization.show_help_default = Config.visualization.show_help_default or true
-- Config.visualization.show_q_default = Config.visualization.show_q_default or true -- Không cần nữa
Config.visualization.path_width_factor = Config.visualization.path_width_factor or (1/7)
Config.visualization.agent_size_factor = Config.visualization.agent_size_factor or 0.35
-- Config.visualization.arrow_length_factor = Config.visualization.arrow_length_factor or 0.3 -- Không cần nữa
-- Config.visualization.arrow_head_factor = Config.visualization.arrow_head_factor or 0.4 -- Không cần nữa

math.randomseed(os.time())

-- Biến toàn cục
local GRID_WIDTH, GRID_HEIGHT, CELL_SIZE, WALL_THICKNESS
local START_X, START_Y, END_X, END_Y
local LEARNING_RATE, DISCOUNT_FACTOR, EPSILON, EPSILON_DECAY, MIN_EPSILON, NUM_EPISODES
local REWARD_GOAL, REWARD_STEP
local actions
local maxStepsPerEpisode

-- Trạng thái ứng dụng và dữ liệu
local appState = 'idle'
local showHelp, isPaused
local algorithmSpeed
local grid, qTable, agent, learnedPath, currentEpisode, currentEpsilon
local currentEpisodePath
local hoveredCell = nil -- <<<<< Lưu ô đang hover

local fontMain
-- ================================================================
--                       LOVE CALLBACKS
-- ================================================================

function love.load()
    fontMain = love.graphics.newFont("fonts/ShareTechMono-Regular.ttf", 13)
    love.graphics.setFont(fontMain)

    GRID_WIDTH = Config.maze.width
    GRID_HEIGHT = Config.maze.height
    CELL_SIZE = Config.maze.cell_size
    WALL_THICKNESS = Config.maze.wall_thickness

    START_X = (Config.start_pos and Config.start_pos.x) or 1
    START_Y = (Config.start_pos and Config.start_pos.y) or 1
    END_X = (Config.end_pos and Config.end_pos.x) or GRID_WIDTH
    END_Y = (Config.end_pos and Config.end_pos.y) or GRID_HEIGHT

    LEARNING_RATE = Config.q_learning.alpha
    DISCOUNT_FACTOR = Config.q_learning.gamma
    EPSILON = Config.q_learning.epsilon_start
    EPSILON_DECAY = Config.q_learning.epsilon_decay
    MIN_EPSILON = Config.q_learning.epsilon_min
    NUM_EPISODES = Config.q_learning.episodes

    REWARD_GOAL = Config.rewards.goal
    REWARD_STEP = Config.rewards.step

    showHelp = Config.visualization.show_help_default
    algorithmSpeed = Config.visualization.initial_speed
    hoveredCell = nil -- Khởi tạo

    appState = 'idle'
    isPaused = false
    grid = {}
    qTable = {}
    agent = {x = START_X, y = START_Y, currentEpisodeSteps = 0, wasExploring = false}
    learnedPath = {}
    currentEpisodePath = {}
    currentEpisode = 0
    currentEpsilon = EPSILON
    -- maxQValueRange không cần nữa
    maxStepsPerEpisode = GRID_WIDTH * GRID_HEIGHT * Config.q_learning.max_steps_per_episode_factor

    actions = { {dx = 0, dy = -1}, {dx = 0, dy = 1}, {dx = 1, dy = 0}, {dx = -1, dy = 0} }

    initializeMazeAndQTable()

    -- Tăng chiều cao cửa sổ
    local windowWidth = GRID_WIDTH * CELL_SIZE
    local windowHeight = GRID_HEIGHT * CELL_SIZE + 110 -- Thêm không gian cho inspector
    love.window.setMode(windowWidth, windowHeight)

    print("Q-Learning Maze (Inspector Mode) Loaded.")
    print("Press 'G' for new maze. Press 'T' to start/resume training.")
    print("Hover mouse over grid to inspect cells.")
end

function love.update(dt)
    -- Theo dõi chuột
    local mx, my = love.mouse.getPosition()
    local gridX = math.floor(mx / CELL_SIZE) + 1
    local gridY = math.floor(my / CELL_SIZE) + 1
    if gridX >= 1 and gridX <= GRID_WIDTH and gridY >= 1 and gridY <= GRID_HEIGHT then
        if not hoveredCell or hoveredCell.x ~= gridX or hoveredCell.y ~= gridY then
             hoveredCell = {x = gridX, y = gridY}
        end
    else
        hoveredCell = nil
    end

    -- Chạy training
    if appState == 'training_step' and not isPaused then
        runTrainingSteps(algorithmSpeed)
    end
end

function love.draw()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)

    -- Vẽ nền ô cơ bản
    drawBaseGrid()

    -- Vẽ highlight cho ô hover
    if hoveredCell then
        love.graphics.setColor(0, 0.5, 1, 0.25) -- Xanh dương nhạt
        love.graphics.rectangle("fill", (hoveredCell.x - 1) * CELL_SIZE, (hoveredCell.y - 1) * CELL_SIZE, CELL_SIZE, CELL_SIZE)
    end
    love.graphics.setColor(1, 1, 1) -- Reset màu

    -- Vẽ tường
    drawMazeWalls()

    -- Vẽ đường đi của episode hiện tại
    if appState == 'training_step' then
         drawCurrentEpisodePath()
    end

    -- Vẽ đường đi đã học
    if (appState == 'trained' or appState == 'showing_path') and learnedPath and #learnedPath > 0 then
        drawLearnedPath()
    end

    -- Vẽ Agent
    drawAgent()

    -- Vẽ điểm bắt đầu/kết thúc
    drawStartEndPoints()

    -- Vẽ thông tin CƠ BẢN
    drawInfoText()

    -- Vẽ thông tin INSPECTOR
    drawInspectorInfo()
end

function love.keypressed(key)
     if key == 'g' then initializeMazeAndQTable()
     elseif key == 't' then startOrResumeTraining()
     elseif key == 'r' then
         if appState == 'trained' or appState == 'paused' or appState == 'showing_path' then
             derivePathFromPolicy(); appState = 'showing_path'; print("Showing learned path...")
         else print("Wait for training to finish or pause it first.") end
     elseif key == 'p' then
         if appState == 'training_step' then isPaused = not isPaused; print(isPaused and "Training Paused." or "Training Resumed.") end
     elseif key == '=' or key == '+' then algorithmSpeed = algorithmSpeed + 1
     elseif key == '-' or key == '_' then algorithmSpeed = math.max(0, algorithmSpeed - 1)
     elseif key == 'h' then showHelp = not showHelp
     elseif key == 'd' then printQTable()
     end
     if key == '+' or key == '=' or key == '-' or key == '_' then print("Algorithm Speed set to:", algorithmSpeed) end
end


-- ================================================================
--                INITIALIZATION AND MAZE GENERATION
-- ================================================================

function initializeMazeAndQTable()
    print("Initializing Grid and Q-Table...")
    grid = {}
    qTable = {}
    learnedPath = {}
    currentEpisodePath = {}
    currentEpisode = 1
    currentEpsilon = EPSILON
    agent.x, agent.y = START_X, START_Y
    agent.currentEpisodeSteps = 0
    agent.wasExploring = false
    appState = 'generating_maze'
    isPaused = false

    for y = 1, GRID_HEIGHT do
        grid[y] = {}
        qTable[y] = {}
        for x = 1, GRID_WIDTH do
            grid[y][x] = {
                x = x, y = y,
                walls = {north = true, south = true, east = true, west = true},
                visited_gen = false, color = {1, 1, 1} -- Màu nền trắng cơ bản
            }
            qTable[y][x] = {}
            for i = 1, #actions do qTable[y][x][i] = 0.0 end
        end
    end

    generateMaze_RecursiveBacktracker_Instant(START_X, START_Y)
    print("Maze generated.")
    appState = 'idle'
end

function generateMaze_RecursiveBacktracker_Instant(startX, startY)
    -- (Giữ nguyên hàm này)
    local stack = {}; local currentCell = grid[startY][startX]; currentCell.visited_gen = true
    local visitedCount = 1; table.insert(stack, currentCell)
    while visitedCount < GRID_WIDTH * GRID_HEIGHT do
        if #stack == 0 then break end
        currentCell = stack[#stack]; local neighbors = {}
        local dx = {0, 0, 1, -1}; local dy = {-1, 1, 0, 0}
        for i = 1, 4 do
            local nx, ny = currentCell.x + dx[i], currentCell.y + dy[i]
            if nx >= 1 and nx <= GRID_WIDTH and ny >= 1 and ny <= GRID_HEIGHT and not grid[ny][nx].visited_gen then
                table.insert(neighbors, grid[ny][nx])
            end
        end
        if #neighbors > 0 then
            local nextCell = neighbors[love.math.random(1, #neighbors)]
            removeWall(currentCell, nextCell); nextCell.visited_gen = true
            visitedCount = visitedCount + 1; table.insert(stack, nextCell)
        else table.remove(stack) end
    end
    -- Không cần reset màu ở đây nữa vì đã là trắng
end

function removeWall(c1, c2)
    -- (Giữ nguyên hàm này)
    local xd=c1.x-c2.x;local yd=c1.y-c2.y
    if xd==1 then c1.walls.west=false;c2.walls.east=false elseif xd==-1 then c1.walls.east=false;c2.walls.west=false end
    if yd==1 then c1.walls.north=false;c2.walls.south=false elseif yd==-1 then c1.walls.south=false;c2.walls.north=false end
end

-- ================================================================
--                   Q-LEARNING CORE LOGIC
-- ================================================================

function startOrResumeTraining()
    -- (Giữ nguyên hàm này)
    if appState == 'idle' or appState == 'trained' or appState == 'paused' then
        if currentEpisode > NUM_EPISODES then print("Training already completed " .. NUM_EPISODES .. " episodes. Press 'G' to reset."); return; end
        appState = 'training_step'; isPaused = false; print("Starting/Resuming Training...")
    elseif appState == 'training_step' then print("Training is already running. Press 'P' to pause/resume.") end
end

function runTrainingSteps(steps)
     -- (Giữ nguyên hàm này, bao gồm logic cập nhật agent.wasExploring)
    if currentEpisode > NUM_EPISODES then
        if appState ~= 'trained' then appState = 'trained'; derivePathFromPolicy(); print("Training finished."); end
        return
    end

    for i = 1, steps do
        if currentEpisode > NUM_EPISODES then break end

        if agent.x == END_X and agent.y == END_Y or agent.currentEpisodeSteps >= maxStepsPerEpisode then
            currentEpisode = currentEpisode + 1
            if currentEpisode > NUM_EPISODES then break end
            currentEpsilon = math.max(MIN_EPSILON, currentEpsilon * EPSILON_DECAY)
            agent.x, agent.y = START_X, START_Y; agent.currentEpisodeSteps = 0
            currentEpisodePath = {{x = agent.x, y = agent.y}}; agent.wasExploring = false
            if currentEpisode % 100 == 0 then print(string.format("Starting Ep: %d/%d (Eps: %.4f)", currentEpisode, NUM_EPISODES, currentEpsilon)) end
        end

        local stateX, stateY = agent.x, agent.y
        local isExploringAction = false; local actionIndex
        if love.math.random() < currentEpsilon then actionIndex = love.math.random(1, #actions); isExploringAction = true
        else actionIndex = getBestAction(stateX, stateY); isExploringAction = false end
        agent.wasExploring = isExploringAction

        local nextX, nextY, reward, isTerminal = takeAction(stateX, stateY, actionIndex)
        updateQValue(stateX, stateY, actionIndex, reward, nextX, nextY)
        -- grid[stateY][stateX].maxQ = getMaxQValue(stateX, stateY) -- Không cần nữa
        agent.x, agent.y = nextX, nextY; agent.currentEpisodeSteps = agent.currentEpisodeSteps + 1
        if currentEpisodePath then table.insert(currentEpisodePath, {x = agent.x, y = agent.y}) end
    end
    -- Không cần calculateMaxQValueRange nữa
end

function updateQValue(sX, sY, actionIdx, reward, nextSX, nextSY)
    -- (Giữ nguyên hàm này)
    local oldQValue = qTable[sY][sX][actionIdx]
    local nextMaxQ = getMaxQValue(nextSX, nextSY)
    local newQValue = oldQValue + LEARNING_RATE * (reward + DISCOUNT_FACTOR * nextMaxQ - oldQValue)
    qTable[sY][sX][actionIdx] = newQValue
end

function takeAction(currentX, currentY, actionIndex)
    -- (Giữ nguyên hàm này)
    local action = actions[actionIndex]; local nextX, nextY = currentX + action.dx, currentY + action.dy
    local reward = REWARD_STEP; local isTerminal = false; local wallHit = false
    if action.dy == -1 and grid[currentY][currentX].walls.north then wallHit = true end
    if action.dy == 1 and grid[currentY][currentX].walls.south then wallHit = true end
    if action.dx == 1 and grid[currentY][currentX].walls.east then wallHit = true end
    if action.dx == -1 and grid[currentY][currentX].walls.west then wallHit = true end
    if nextX < 1 or nextX > GRID_WIDTH or nextY < 1 or nextY > GRID_HEIGHT then wallHit = true end

    if wallHit then nextX, nextY = currentX, currentY end
    if nextX == END_X and nextY == END_Y then reward = REWARD_GOAL; isTerminal = true end
    return nextX, nextY, reward, isTerminal
end

function getMaxQValue(stateX, stateY)
    -- (Giữ nguyên hàm này)
    local maxQ = -math.huge
    if qTable and qTable[stateY] and qTable[stateY][stateX] then
        for i = 1, #actions do maxQ = math.max(maxQ, qTable[stateY][stateX][i] or 0.0) end
    else return 0 end
    if maxQ == -math.huge then return 0 end
    return maxQ
end

function getBestAction(stateX, stateY)
   -- (Giữ nguyên hàm này)
   local bestAction = 1; local maxQ = -math.huge; local foundAction = false
   if qTable and qTable[stateY] and qTable[stateY][stateX] then
       for i = 1, #actions do
           local currentQ = qTable[stateY][stateX][i] or 0.0
           if currentQ > maxQ then maxQ = currentQ; bestAction = i; foundAction = true end
       end
   else return love.math.random(1, #actions) end
   if not foundAction then return love.math.random(1, #actions) end

   local bestActions = {}
   for i = 1, #actions do
     local currentQ = qTable[stateY][stateX][i] or 0.0
     if math.abs(currentQ - maxQ) < 1e-6 then table.insert(bestActions, i) end
   end
   if #bestActions > 1 then return bestActions[love.math.random(1, #bestActions)]
   else return bestAction end
end

function derivePathFromPolicy()
    -- (Giữ nguyên hàm này)
    learnedPath = {}; local currentX, currentY = START_X, START_Y
    local steps = 0; local maxSteps = GRID_WIDTH * GRID_HEIGHT * 1.5; local pathSet = {}
    while steps < maxSteps do
        local key = currentY .. "," .. currentX
        if pathSet[key] then print("Error deriving path: Loop detected."); learnedPath={}; return; end; pathSet[key] = true
        table.insert(learnedPath, {x = currentX, y = currentY})
        if currentX == END_X and currentY == END_Y then print("Derived path found. Length:", #learnedPath); return; end
        local bestActionIndex = getBestAction(currentX, currentY)
        if not actions[bestActionIndex] then print("Error deriving path: Invalid best action index."); learnedPath={}; return; end
        local action = actions[bestActionIndex]; local nextX, nextY = currentX + action.dx, currentY + action.dy
        if nextX < 1 or nextX > GRID_WIDTH or nextY < 1 or nextY > GRID_HEIGHT then print("Error deriving path: Policy leads OOB."); learnedPath={}; return; end
        local wallHit = false
        if action.dy == -1 and grid[currentY][currentX].walls.north then wallHit = true end
        if action.dy == 1 and grid[currentY][currentX].walls.south then wallHit = true end
        if action.dx == 1 and grid[currentY][currentX].walls.east then wallHit = true end
        if action.dx == -1 and grid[currentY][currentX].walls.west then wallHit = true end
        if wallHit then print("Error deriving path: Policy hits wall between ("..currentX..","..currentY..") and ("..nextX..","..nextY..")"); learnedPath={}; return; end
        currentX, currentY = nextX, nextY; steps = steps + 1
    end
    print("Error deriving path: Max steps reached."); learnedPath = {}
end

-- ================================================================
--                     HELPER FUNCTIONS (Print Q-Table)
-- ================================================================

function printQTable()
    -- (Giữ nguyên hàm này)
    print("\n--- Dumping Q-Table ---")
    if not qTable then print("Q-Table does not exist yet."); print("--- End Q-Table Dump ---"); return; end
    local actionNames = {"Up", "Down", "East", "West"}
    for y = 1, GRID_HEIGHT do for x = 1, GRID_WIDTH do
        if qTable[y] and qTable[y][x] then
            local values = {}
            for i = 1, #actions do table.insert(values, string.format("%s: %.2f", actionNames[i] or "A"..i, qTable[y][x][i] or 0.0)) end
            print(string.format("Cell(%d, %d): %s", x, y, table.concat(values, ", ")))
        else print(string.format("Cell(%d, %d): No Q-values", x, y)) end end end
    print("--- End Q-Table Dump ---")
end

-- ================================================================
--                      DRAWING FUNCTIONS
-- ================================================================

function drawBaseGrid()
    -- (Giữ nguyên hàm này)
    love.graphics.setColor(1, 1, 1)
    for y=1,GRID_HEIGHT do for x=1,GRID_WIDTH do
        love.graphics.rectangle("fill", (x-1)*CELL_SIZE, (y-1)*CELL_SIZE, CELL_SIZE, CELL_SIZE)
    end end
end

-- Xóa hàm drawQValueColors(), drawPolicyArrows(), calculateMaxQValueRange()

function drawMazeWalls()
    -- (Giữ nguyên hàm này)
    local wallThickness = WALL_THICKNESS
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9); love.graphics.setLineWidth(wallThickness)
    for y=1,GRID_HEIGHT do for x=1,GRID_WIDTH do
        local cell = grid[y][x]; local sx=(x-1)*CELL_SIZE; local sy=(y-1)*CELL_SIZE
        if cell.walls.north then love.graphics.line(sx,sy,sx+CELL_SIZE,sy) end
        if cell.walls.south then love.graphics.line(sx,sy+CELL_SIZE,sx+CELL_SIZE,sy+CELL_SIZE) end
        if cell.walls.east then love.graphics.line(sx+CELL_SIZE,sy,sx+CELL_SIZE,sy+CELL_SIZE) end
        if cell.walls.west then love.graphics.line(sx,sy,sx,sy+CELL_SIZE) end
    end end
    love.graphics.setLineWidth(1)
end

function drawCurrentEpisodePath()
    -- (Giữ nguyên hàm này)
    if not currentEpisodePath or #currentEpisodePath < 2 then return end
    love.graphics.setColor(1, 0.6, 0, 0.5)
    local pathWidthFactor = Config.visualization.path_width_factor or (1/7)
    love.graphics.setLineWidth(math.max(1, math.floor(CELL_SIZE * pathWidthFactor * 0.6)))
    local points = {}
    for _, p in ipairs(currentEpisodePath) do table.insert(points, (p.x - 0.5) * CELL_SIZE); table.insert(points, (p.y - 0.5) * CELL_SIZE) end
    if #points >= 4 then love.graphics.line(points) end
    love.graphics.setLineWidth(1)
end

function drawLearnedPath()
    -- (Giữ nguyên hàm này)
    if not learnedPath or #learnedPath < 1 then return end
    love.graphics.setColor(1, 1, 0, 0.8)
    local pathWidthFactor = Config.visualization.path_width_factor or (1/7)
    love.graphics.setLineWidth(math.max(1, CELL_SIZE * pathWidthFactor))
    local points = {}
    for i, cp in ipairs(learnedPath) do table.insert(points, (cp.x-0.5)*CELL_SIZE); table.insert(points, (cp.y-0.5)*CELL_SIZE) end
    if #points >= 4 then love.graphics.line(points) end
    love.graphics.setLineWidth(1)
end

function drawAgent()
    -- (Giữ nguyên hàm này, vẫn đổi màu explore)
   if appState == 'training_step' then
      if agent.wasExploring then love.graphics.setColor(0, 1, 1, 0.9) -- Cyan explore
      else love.graphics.setColor(1, 0.7, 0, 0.9) end -- Orange exploit
      local agentSizeFactor = Config.visualization.agent_size_factor or 0.35
      love.graphics.circle("fill", (agent.x - 0.5) * CELL_SIZE, (agent.y - 0.5) * CELL_SIZE, CELL_SIZE * agentSizeFactor)
   end
   love.graphics.setColor(1,1,1) -- Reset màu
end

function drawStartEndPoints()
    -- (Giữ nguyên hàm này)
    love.graphics.setColor(0, 1, 0, 0.9); local sx = (START_X - 1) * CELL_SIZE; local sy = (START_Y - 1) * CELL_SIZE
    love.graphics.rectangle("fill", sx + 2, sy + 2, CELL_SIZE - 4, CELL_SIZE - 4)
    love.graphics.setColor(1, 0, 0, 0.9); local ex = (END_X - 1) * CELL_SIZE; local ey = (END_Y - 1) * CELL_SIZE
    love.graphics.rectangle("fill", ex + 2, ey + 2, CELL_SIZE - 4, CELL_SIZE - 4)
end

-- <<<<< HÀM VẼ INFO CƠ BẢN (ĐÃ SỬA) >>>>>
function drawInfoText()
    local yPos = GRID_HEIGHT * CELL_SIZE + 5
    love.graphics.setColor(1, 1, 1)

    -- Status text
    local status = "Status: " .. appState
    if appState == 'training_step' then status = string.format("Status: Training (Ep %d/%d, Eps: %.3f) %s", currentEpisode, NUM_EPISODES, currentEpsilon, isPaused and "[PAUSED - P]" or "")
    elseif appState == 'trained' then status = "Status: Training Finished (" .. NUM_EPISODES .. " eps)"
    elseif appState == 'showing_path' then status = "Status: Showing Learned Path" end
    love.graphics.print(status, 10, yPos)

    -- Speed text
    local speedText = "Speed (Steps/Frame): " .. algorithmSpeed .. " (+/-)"
    love.graphics.print(speedText, 10, yPos + 15)

    -- Help text (Nếu bật)
    if showHelp then
         local helpY = yPos + 30 -- Điều chỉnh vị trí bắt đầu của help text
         love.graphics.print("Keys: G=New | T=Train | P=Pause | R=Path", 10, helpY)
         love.graphics.print("+/-=Speed | H=Help | D=Dump Q", 10, helpY + 15) -- Đã xóa Q, X
    end
end

-- <<<<< HÀM VẼ INFO INSPECTOR (MỚI) >>>>>
function drawInspectorInfo()
    local infoStartY = GRID_HEIGHT * CELL_SIZE + 45 -- Vị trí Y bắt đầu Inspector
    local lineHeight = 15
    local areaHeight = 110 - 55 -- Chiều cao khu vực info inspector

    -- Vẽ nền cho khu vực Inspector
    love.graphics.setColor(0.15, 0.15, 0.15, 0.9) -- Nền xám đậm hơn một chút
    love.graphics.rectangle("fill", 0, infoStartY - 5, love.graphics.getWidth(), areaHeight + 5)
    love.graphics.setColor(1, 1, 1) -- Reset màu chữ về trắng

    if hoveredCell then
        local hx, hy = hoveredCell.x, hoveredCell.y
        local cellInfoText = string.format("Inspecting Cell: (%d, %d)", hx, hy)
        love.graphics.print(cellInfoText, 10, infoStartY)

        if qTable and qTable[hy] and qTable[hy][hx] then
            local maxQ = getMaxQValue(hx, hy)
            local bestActionIndex = getBestAction(hx, hy)
            local actionNames = {"Up", "Down", "East", "West"}
            local bestActionName = actionNames[bestActionIndex] or "N/A"

            local maxQText = string.format("Max Q-Value: %.3f", maxQ)
            love.graphics.print(maxQText, 10, infoStartY + lineHeight * 1)

            local bestActionText = string.format("Best Action: %s", bestActionName)
            love.graphics.print(bestActionText, 10, infoStartY + lineHeight * 2)

            local qVals = qTable[hy][hx]
            local qValText = string.format("Q: U:%.2f D:%.2f E:%.2f W:%.2f",
                                           qVals[1] or 0, qVals[2] or 0, qVals[3] or 0, qVals[4] or 0)
            love.graphics.print(qValText, 10, infoStartY + lineHeight * 3)
        else
            love.graphics.print("No Q-data for this cell.", 10, infoStartY + lineHeight * 1)
        end
    else
        love.graphics.print("Hover over the grid to inspect a cell.", 10, infoStartY)
    end
end
