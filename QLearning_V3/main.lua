-- main.lua (Phiên bản HOÀN CHỈNH - Q-learning 50:50 Layout, 10x10 Q-Grid, 5x5 Sim)

-- Load configuration file safely
local success, Config = pcall(require, "config")
if not success then
    error("Could not load config.lua! Make sure it exists and has correct syntax.\nError: " .. tostring(Config))
end
-- Cung cấp giá trị mặc định (Quan trọng: đảm bảo grid là 5x5)
Config.maze = Config.maze or {}
Config.maze.width = Config.maze.width or 5 -- <<< Đảm bảo là 5
Config.maze.height = Config.maze.height or 5 -- <<< Đảm bảo là 5
Config.maze.wall_thickness = Config.maze.wall_thickness or 1 -- Có thể giảm độ dày tường cho ô lớn

Config.q_learning = Config.q_learning or {}
Config.q_learning.episodes = Config.q_learning.episodes or 5000
Config.q_learning.alpha = Config.q_learning.alpha or 0.1
Config.q_learning.gamma = Config.q_learning.gamma or 0.9
Config.q_learning.epsilon_start = Config.q_learning.epsilon_start or 1.0
Config.q_learning.epsilon_decay = Config.q_learning.epsilon_decay or 0.9995 -- Có thể cần decay chậm hơn cho lưới nhỏ
Config.q_learning.epsilon_min = Config.q_learning.epsilon_min or 0.01
Config.q_learning.max_steps_per_episode_factor = Config.q_learning.max_steps_per_episode_factor or 1.5 -- Giảm hệ số cho lưới nhỏ

Config.rewards = Config.rewards or {}
Config.rewards.goal = Config.rewards.goal or 100
Config.rewards.step = Config.rewards.step or -0.1 -- Phần thưởng bước đi có thể giữ nguyên

Config.visualization = Config.visualization or {}
Config.visualization.initial_speed = Config.visualization.initial_speed or 5
Config.visualization.show_help_default = Config.visualization.show_help_default or true
Config.visualization.path_width_factor = Config.visualization.path_width_factor or (1/10) -- Đường path mảnh hơn trên ô lớn
Config.visualization.agent_size_factor = Config.visualization.agent_size_factor or 0.3 -- Agent nhỏ hơn tương đối trên ô lớn

math.randomseed(os.time())

-- Layout constants (Ví dụ cho cửa sổ 1280x720)
local WINDOW_WIDTH = 1280
local WINDOW_HEIGHT = 720
local INFO_AREA_HEIGHT = 0 -- Tạm thời không cần info area riêng
local AVAILABLE_HEIGHT = WINDOW_HEIGHT - INFO_AREA_HEIGHT

-- Biến toàn cục cho kích thước và vị trí
local GRID_WIDTH, GRID_HEIGHT
local Q_CELL_SIZE -- Kích thước ô nhỏ bên trái (10x10 grid)
local CELL_SIZE   -- Kích thước ô lớn bên phải (5x5 grid, = 2 * Q_CELL_SIZE)
local Q_GRID_DIM = 14 -- Kích thước grid hiển thị Q-Table (10x10)
local Q_TABLE_PANEL_WIDTH
local SIM_START_X

local WALL_THICKNESS
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
local qTableMinMax = {min = 0, max = 0} -- Lưu min/max của *toàn bộ* Q-table để tô màu

local fontMain, fontQValue -- Font cho giá trị Q nhỏ

-- ================================================================
--                       LOVE CALLBACKS
-- ================================================================

function love.load()
    -- Load fonts
    fontMain = love.graphics.newFont("fonts/ShareTechMono-Regular.ttf", 13)
    fontQValue = love.graphics.newFont("fonts/ShareTechMono-Regular.ttf", 13) -- Font rất nhỏ
    love.graphics.setFont(fontMain)

    -- Load config và thiết lập biến kích thước lưới (QUAN TRỌNG: 5x5)
    GRID_WIDTH = Config.maze.width or 5
    GRID_HEIGHT = Config.maze.height or 5
    WALL_THICKNESS = Config.maze.wall_thickness or 1

    Q_CELL_SIZE = 45
    CELL_SIZE = 2 * Q_CELL_SIZE -- Kích thước ô mô phỏng = 2 * ô Q-table
    Q_TABLE_PANEL_WIDTH = Q_GRID_DIM * Q_CELL_SIZE
    SIM_START_X = Q_TABLE_PANEL_WIDTH

    print(string.format("Window: %dx%d, QGrid: %dx%d (Cell: %d), SimGrid: %dx%d (Cell: %d)",
                        WINDOW_WIDTH, WINDOW_HEIGHT, Q_GRID_DIM, Q_GRID_DIM, Q_CELL_SIZE, GRID_WIDTH, GRID_HEIGHT, CELL_SIZE))


    -- Thiết lập các biến khác
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
    maxStepsPerEpisode = GRID_WIDTH * GRID_HEIGHT * Config.q_learning.max_steps_per_episode_factor
    actions = { {dx = 0, dy = -1}, {dx = 0, dy = 1}, {dx = 1, dy = 0}, {dx = -1, dy = 0} } -- 1:U, 2:D, 3:E, 4:W

    -- Khởi tạo trạng thái
    appState = 'idle'; isPaused = false; grid = {}; qTable = {}
    agent = {x = START_X, y = START_Y, currentEpisodeSteps = 0, wasExploring = false}
    learnedPath = {}; currentEpisodePath = {}; currentEpisode = 0; currentEpsilon = EPSILON
    qTableMinMax = {min = 0, max = 0, needsUpdate = true} -- Thêm flag cần cập nhật

    initializeMazeAndQTable()

    love.window.setMode(WINDOW_WIDTH, WINDOW_HEIGHT)

    print("Q-Learning Maze (50:50 Q-Grid Layout) Loaded.")
    print("Press 'G' for new maze. Press 'T' to start/resume training.")
end

function love.update(dt)
    -- Không cần theo dõi chuột

    -- Chạy training
    if appState == 'training_step' and not isPaused then
        runTrainingSteps(algorithmSpeed)
        qTableMinMax.needsUpdate = true -- Đánh dấu cần cập nhật min/max sau khi train
    end

    -- Cập nhật min/max cho Q-Table để tô màu (chỉ khi cần)
    if qTableMinMax.needsUpdate then
        calculateFullQTableRange()
        qTableMinMax.needsUpdate = false
    end
end


function love.draw()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)

    love.graphics.push()
    love.graphics.translate(10, 60)
    

    -- 1. Vẽ Panel Q-Table Grid (Bên trái)
    drawQTableGridPanel()

    -- 2. Vẽ Phần Mô phỏng (Bên phải)
    love.graphics.push()
    love.graphics.translate(SIM_START_X + 2, 0)

    drawBaseGrid()
    drawMazeWalls()
    if appState == 'training_step' then drawCurrentEpisodePath() end
    if (appState == 'trained' or appState == 'showing_path') and learnedPath and #learnedPath > 0 then drawLearnedPath() end
    drawAgent()
    drawStartEndPoints()

    love.graphics.pop()

    -- <<<< VẼ ĐƯỜNG PHÂN CÁCH >>>>
    love.graphics.setColor(0.4, 0.4, 0.4, 0.7) -- Màu xám nhạt
    love.graphics.setLineWidth(1)
    love.graphics.line(SIM_START_X, 0, SIM_START_X, WINDOW_HEIGHT)
    love.graphics.setColor(1,1,1) -- Reset màu
    -- <<<< KẾT THÚC VẼ ĐƯỜNG PHÂN CÁCH >>>>

    -- 3. Vẽ Thông tin cơ bản (Overlay góc trên trái)

    love.graphics.pop()

    drawInfoText()
end

function love.keypressed(key)
    if key == 'g' then 
        initializeMazeAndQTable()
        qTableMinMax.needsUpdate = true 
    
        elseif key == 't' then startOrResumeTraining()
        elseif key == 'r' then
            if appState == 'trained' or appState == 'paused' then
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
    grid = {}; qTable = {}
    learnedPath = {}; currentEpisodePath = {}
    currentEpisode = 1; currentEpsilon = EPSILON
    agent.x, agent.y = START_X, START_Y
    agent.currentEpisodeSteps = 0; agent.wasExploring = false
    appState = 'generating_maze'; isPaused = false

    for y = 1, GRID_HEIGHT do
        grid[y] = {}
        qTable[y] = {}
        for x = 1, GRID_WIDTH do
            grid[y][x] = { x = x, y = y, walls = {north = true, south = true, east = true, west = true}, visited_gen = false, color = {1, 1, 1} }
            qTable[y][x] = {}
            for i = 1, #actions do qTable[y][x][i] = 0.0 end
        end
    end
    generateMaze_RecursiveBacktracker_Instant(START_X, START_Y)
    print("Maze generated.")
    appState = 'idle'
    qTableMinMax.needsUpdate = true -- Cần tính min/max lần đầu
end

function generateMaze_RecursiveBacktracker_Instant(startX, startY)
    -- (Giữ nguyên)
    local stack = {}; local currentCell = grid[startY][startX]; currentCell.visited_gen = true
    local visitedCount = 1; table.insert(stack, currentCell)
    while visitedCount < GRID_WIDTH * GRID_HEIGHT do
        if #stack == 0 then break end
        currentCell = stack[#stack]; local neighbors = {}
        local dx={0,0,1,-1}; local dy={-1,1,0,0}
        for i=1,4 do local nx,ny=currentCell.x+dx[i],currentCell.y+dy[i] if nx>=1 and nx<=GRID_WIDTH and ny>=1 and ny<=GRID_HEIGHT and not grid[ny][nx].visited_gen then table.insert(neighbors,grid[ny][nx]) end end
        if #neighbors > 0 then local nextCell=neighbors[love.math.random(1,#neighbors)]; removeWall(currentCell,nextCell); nextCell.visited_gen=true; visitedCount=visitedCount+1; table.insert(stack,nextCell)
        else table.remove(stack) end
    end
end

function removeWall(c1, c2)
    -- (Giữ nguyên)
    local xd=c1.x-c2.x; local yd=c1.y-c2.y
    if xd==1 then c1.walls.west=false; c2.walls.east=false elseif xd==-1 then c1.walls.east=false; c2.walls.west=false end
    if yd==1 then c1.walls.north=false; c2.walls.south=false elseif yd==-1 then c1.walls.south=false; c2.walls.north=false end
end

-- ================================================================
--                   Q-LEARNING CORE LOGIC
-- ================================================================
-- (Các hàm: startOrResumeTraining, runTrainingSteps, updateQValue, takeAction,
--  getMaxQValue, getBestAction, derivePathFromPolicy giữ nguyên)
function startOrResumeTraining()
    if appState == 'idle' or appState == 'trained' or appState == 'paused' then
        if currentEpisode > NUM_EPISODES then print("Training already completed " .. NUM_EPISODES .. " episodes. Press 'G' to reset."); return; end
        appState = 'training_step'; isPaused = false; print("Starting/Resuming Training...")
    elseif appState == 'training_step' then print("Training is already running. Press 'P' to pause/resume.") end
end

function runTrainingSteps(steps)
    if currentEpisode > NUM_EPISODES then
        if appState ~= 'trained' then appState = 'trained'; derivePathFromPolicy(); print("Training finished."); end
        return
    end

    local qChanged = false
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
        local qBefore = qTable[stateY][stateX][actionIndex]
        updateQValue(stateX, stateY, actionIndex, reward, nextX, nextY)
        if qTable[stateY][stateX][actionIndex] ~= qBefore then qChanged = true end -- Check if Q actually changed
        agent.x, agent.y = nextX, nextY; agent.currentEpisodeSteps = agent.currentEpisodeSteps + 1
        if currentEpisodePath then table.insert(currentEpisodePath, {x = agent.x, y = agent.y}) end
    end
    -- Chỉ đánh dấu cần cập nhật min/max nếu có giá trị Q thực sự thay đổi
    if qChanged then qTableMinMax.needsUpdate = true end
end

function updateQValue(sX, sY, actionIdx, reward, nextSX, nextSY)
    local oldQValue = qTable[sY][sX][actionIdx]
    local nextMaxQ = getMaxQValue(nextSX, nextSY)
    local newQValue = oldQValue + LEARNING_RATE * (reward + DISCOUNT_FACTOR * nextMaxQ - oldQValue)
    -- Chỉ cập nhật nếu giá trị thực sự thay đổi một chút (tránh lỗi làm tròn không cần thiết)
    if math.abs(newQValue - oldQValue) > 1e-9 then
        qTable[sY][sX][actionIdx] = newQValue
    end
end

function takeAction(currentX, currentY, actionIndex)
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
    local maxQ = -math.huge
    if qTable and qTable[stateY] and qTable[stateY][stateX] then
        for i = 1, #actions do maxQ = math.max(maxQ, qTable[stateY][stateX][i] or 0.0) end
    else return 0 end
    if maxQ == -math.huge then return 0 end
    return maxQ
end

function getBestAction(stateX, stateY)
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
    learnedPath = {}; local currentX, currentY = START_X, START_Y
    local steps = 0; local maxSteps = GRID_WIDTH * GRID_HEIGHT * 2; local pathSet = {} -- Tăng max steps một chút
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
--         HELPER FUNCTIONS (Print Q-Table & Calculate Range)
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

-- Hàm tính min/max của TOÀN BỘ giá trị Q để tô màu heatmap
function calculateFullQTableRange()
    if not qTable then qTableMinMax = {min=0, max=0}; return end

    local minVal, maxVal = math.huge, -math.huge
    local foundValue = false
    for y = 1, GRID_HEIGHT do
        for x = 1, GRID_WIDTH do
            if qTable[y] and qTable[y][x] then
                for i = 1, #actions do
                    local qVal = qTable[y][x][i]
                    if type(qVal) == "number" then
                        minVal = math.min(minVal, qVal)
                        maxVal = math.max(maxVal, qVal)
                        foundValue = true
                    end
                end
            end
        end
    end

    if foundValue then
        -- Xử lý trường hợp chỉ có 1 giá trị hoặc tất cả bằng nhau
        if maxVal <= minVal then
             maxVal = minVal + 1 -- Tạo một khoảng nhỏ để tránh chia cho 0
        end
        qTableMinMax.min = minVal
        qTableMinMax.max = maxVal
    else
        qTableMinMax.min = 0
        qTableMinMax.max = 1 -- Giá trị mặc định nếu bảng rỗng
    end
    -- print("Updated Q-Table Range:", qTableMinMax.min, qTableMinMax.max) -- Debug
end


-- ================================================================
--                      DRAWING FUNCTIONS
-- ================================================================

-- <<<<< HÀM VẼ Q-TABLE GRID PANEL (MỚI) >>>>>
function drawQTableGridPanel()
    if not Q_CELL_SIZE then
        print("[Warning] Q_CELL_SIZE is nil, skipping Q-table rendering.")
        return
    end

    love.graphics.push()

    -- Nền panel trái
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.rectangle("fill", 0, 0, Q_TABLE_PANEL_WIDTH, WINDOW_HEIGHT)

    love.graphics.setFont(fontQValue)
    local gridLineWidth = 0.5

    -- Lưới mỏng 10x10
    love.graphics.setColor(0.4, 0.4, 0.4, 0.4)
    love.graphics.setLineWidth(gridLineWidth)
    for i = 0, Q_GRID_DIM do
        love.graphics.line(i * Q_CELL_SIZE, 0, i * Q_CELL_SIZE, Q_GRID_DIM * Q_CELL_SIZE)
        love.graphics.line(0, i * Q_CELL_SIZE, Q_GRID_DIM * Q_CELL_SIZE, i * Q_CELL_SIZE)
    end

    if not qTable then
        love.graphics.pop()
        return
    end

    local minQ = qTableMinMax.min or 0
    local maxQ = qTableMinMax.max or 1
    local qRange = math.max(1e-6, maxQ - minQ)

    for y = 1, GRID_HEIGHT do
        for x = 1, GRID_WIDTH do
            local qVals = qTable[y] and qTable[y][x]
            if qVals then
                local baseX = (x - 1) * 2 * Q_CELL_SIZE
                local baseY = (y - 1) * 2 * Q_CELL_SIZE

                local positions = {
                    {x = baseX, y = baseY},                              -- Up
                    {x = baseX, y = baseY + Q_CELL_SIZE},                -- Down
                    {x = baseX + Q_CELL_SIZE, y = baseY},                -- East
                    {x = baseX + Q_CELL_SIZE, y = baseY + Q_CELL_SIZE}   -- West
                }

                for i = 1, 4 do
                    local qVal = qVals[i] or 0
                    local norm = (qVal - minQ) / qRange
                    norm = math.max(0, math.min(1, norm))

                    local r, g, b
                    -- Blue → Cyan → Green → Yellow → Red
                    if norm < 0.33 then
                        -- Midnight Blue → Teal
                        local t = norm / 0.33
                        r = 0
                        g = t * 0.4
                        b = 0.4 + t * 0.4
                    elseif norm < 0.66 then
                        -- Teal → Light Green
                        local t = (norm - 0.33) / 0.33
                        r = 0
                        g = 0.4 + t * 0.6
                        b = 0.8 - t * 0.8
                    else
                        -- Light Green → Gold
                        local t = (norm - 0.66) / 0.34
                        r = t * 1.0
                        g = 1.0 - t * 0.3
                        b = 0
                    end

                    local px = positions[i].x
                    local py = positions[i].y

                    love.graphics.setColor(r, g, b, 0.6)
                    love.graphics.rectangle("fill", px + gridLineWidth, py + gridLineWidth,
                        Q_CELL_SIZE - 2 * gridLineWidth, Q_CELL_SIZE - 2 * gridLineWidth)

                    -- Text
                    local qStr = string.format("%.1f", qVal)
                    local brightness = r * 0.299 + g * 0.587 + b * 0.114
                    love.graphics.setColor(brightness > 0.6 and 0 or 1,
                                           brightness > 0.6 and 0 or 1,
                                           brightness > 0.6 and 0 or 1)
                    love.graphics.printf(qStr, px, py + Q_CELL_SIZE / 2 - fontQValue:getHeight() / 2,
                        Q_CELL_SIZE, "center")
                end
            end
        end
    end

    -- Viền block 2x2 rõ hơn
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(2)
    for i = 0, GRID_WIDTH do
        love.graphics.line(i * 2 * Q_CELL_SIZE, 0, i * 2 * Q_CELL_SIZE, Q_GRID_DIM * Q_CELL_SIZE)
    end
    for i = 0, GRID_HEIGHT do
        love.graphics.line(0, i * 2 * Q_CELL_SIZE, Q_GRID_DIM * Q_CELL_SIZE, i * 2 * Q_CELL_SIZE)
    end
    love.graphics.setLineWidth(1)

    -- Viền phân cách panel
    love.graphics.setColor(0.2, 0.2, 0.2, 0.0)
    love.graphics.rectangle("fill", Q_TABLE_PANEL_WIDTH, 0, 2, WINDOW_HEIGHT)

    love.graphics.pop()
    love.graphics.setFont(fontMain)
    love.graphics.setColor(1, 1, 1)
end


function drawBaseGrid()
    love.graphics.setColor(0.92, 0.92, 0.92) -- <<<< Màu trắng ngà / xám rất nhạt
    for y=1, GRID_HEIGHT do 
        for x=1, GRID_WIDTH do
            love.graphics.rectangle("fill", (x-1)*CELL_SIZE, (y-1)*CELL_SIZE, CELL_SIZE, CELL_SIZE)
        end 
    end
    love.graphics.setColor(1, 1, 1) -- Reset màu
end

function drawMazeWalls()
    -- (Giữ nguyên hàm này)
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.setLineWidth(WALL_THICKNESS)
    
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
    local pathWidthFactor = Config.visualization.path_width_factor or (1/10)
    love.graphics.setLineWidth(math.max(1, math.floor(CELL_SIZE * pathWidthFactor * 0.6)))
    local points = {}
    for _, p in ipairs(currentEpisodePath) do table.insert(points, (p.x - 0.5) * CELL_SIZE); table.insert(points, (p.y - 0.5) * CELL_SIZE) end
    if #points >= 4 then love.graphics.line(points) end
    love.graphics.setLineWidth(1)
end

function drawLearnedPath()
    -- (Giữ nguyên hàm này)
    if not learnedPath or #learnedPath < 1 then return end
    love.graphics.setColor(129/255, 6/255, 166/255, 0.8)
    local pathWidthFactor = Config.visualization.path_width_factor or (1/10)
    love.graphics.setLineWidth(math.max(1, CELL_SIZE * 0.1))
    local points = {}
    for i, cp in ipairs(learnedPath) do table.insert(points, (cp.x-0.5)*CELL_SIZE); table.insert(points, (cp.y-0.5)*CELL_SIZE) end
    if #points >= 4 then love.graphics.line(points) end
    love.graphics.setLineWidth(1)
end

function drawAgent()
    -- (Giữ nguyên hàm này)
   if appState == 'training_step' then
      if agent.wasExploring then love.graphics.setColor(0, 1, 1, 0.8) -- Cyan explore
      else love.graphics.setColor(1, 0.7, 0, 0.9) end -- Orange exploit
      local agentSizeFactor = Config.visualization.agent_size_factor or 0.3
      love.graphics.circle("fill", (agent.x - 0.5) * CELL_SIZE, (agent.y - 0.5) * CELL_SIZE, CELL_SIZE * 0.15)
   end
   love.graphics.setColor(1,1,1)
end


function drawStartEndPoints()
    -- === START ===
    local sx = (START_X - 0.5) * CELL_SIZE
    local sy = (START_Y - 0.5) * CELL_SIZE
    local r_start = CELL_SIZE * 0.2

    -- Vòng tròn xanh lá + viền trắng
    love.graphics.setColor(0, 1, 0, 0.85)
    love.graphics.circle("fill", sx, sy, r_start)

    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", sx, sy, r_start)

    -- === END ===
    local ex = (END_X - 0.5) * CELL_SIZE
    local ey = (END_Y - 0.5) * CELL_SIZE
    local r_outer = CELL_SIZE * 0.20
    local r_mid   = CELL_SIZE * 0.18
    local r_inner = CELL_SIZE * 0.08

    -- Target đỏ trắng 3 lớp
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", ex, ey, r_outer)

    love.graphics.setColor(1, 0, 0, 0.95)
    love.graphics.circle("fill", ex, ey, r_mid)

    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", ex, ey, r_inner)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end


-- <<<<< HÀM VẼ INFO CƠ BẢN (Overlay góc trên trái) >>>>>
function drawInfoText()
    local yPos = 8
    local xPos = 8
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fontMain)

    -- Vẽ nền mờ cho text để dễ đọc hơn (tùy chọn)
    local textBgHeight = 35 + (showHelp and 15 or 0)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 1280, textBgHeight) -- Vẽ nền chỉ trong panel trái
    love.graphics.setColor(1, 1, 1)


    local status = "Status: " .. appState
    if appState == 'training_step' then status = string.format("Status: Training (Ep %d/%d, Eps: %.3f) %s", currentEpisode, NUM_EPISODES, currentEpsilon, isPaused and "[P]" or "")
    elseif appState == 'trained' then status = "Status: Training Finished (" .. NUM_EPISODES .. " eps)"
    elseif appState == 'showing_path' then status = "Status: Showing Learned Path" end
    love.graphics.print(status, xPos, yPos)

    local speedText = "Speed: " .. algorithmSpeed .. " (+/-)"
    love.graphics.print(speedText, xPos, yPos + 15)

    if showHelp then
         love.graphics.print("Keys: G|T|P|R|H|D|+|-", xPos, yPos + 30)
    end
end
