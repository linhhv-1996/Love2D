-- main.lua (Phiên bản HOÀN CHỈNH - Q-learning Maze Solver Step-by-Step with Config)

-- Load configuration file safely
local success, Config = pcall(require, "config")
if not success then
    error("Could not load config.lua! Make sure it exists and has correct syntax.\nError: " .. tostring(Config))
end
-- Cung cấp giá trị mặc định nếu một số mục bị thiếu trong config (tùy chọn)
-- Điều này giúp tránh lỗi nếu người dùng xóa bớt dòng trong config.lua
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
Config.visualization.show_q_default = Config.visualization.show_q_default or true
Config.visualization.path_width_factor = Config.visualization.path_width_factor or (1/7)
Config.visualization.agent_size_factor = Config.visualization.agent_size_factor or 0.35

math.randomseed(os.time())

-- Biến toàn cục sẽ được thiết lập trong love.load
local GRID_WIDTH, GRID_HEIGHT, CELL_SIZE, WALL_THICKNESS
local START_X, START_Y, END_X, END_Y
local LEARNING_RATE, DISCOUNT_FACTOR, EPSILON, EPSILON_DECAY, MIN_EPSILON, NUM_EPISODES
local REWARD_GOAL, REWARD_STEP
local actions -- Bảng hành động
local maxStepsPerEpisode

-- Trạng thái ứng dụng và dữ liệu
local appState = 'idle'
local showHelp, showQValues, isPaused
local algorithmSpeed
local grid, qTable, agent, learnedPath, currentEpisode, currentEpsilon, maxQValueRange

local fontMain
-- ================================================================
--                        LOVE CALLBACKS
-- ================================================================

function love.load()
    -- Load font
    fontMain = love.graphics.newFont("fonts/ShareTechMono-Regular.ttf", 13)
    love.graphics.setFont(fontMain)
    -- Thiết lập các biến toàn cục từ Config đã load
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
    showQValues = Config.visualization.show_q_default
    algorithmSpeed = Config.visualization.initial_speed

    -- Khởi tạo các biến trạng thái và dữ liệu khác
    appState = 'idle'
    isPaused = false
    grid = {}
    qTable = {}
    agent = {x = START_X, y = START_Y, currentEpisodeSteps = 0}
    learnedPath = {}
    currentEpisode = 0 -- Sẽ được đặt lại thành 1 trong initialize
    currentEpsilon = EPSILON
    maxQValueRange = {min = 0, max = 0}
    maxStepsPerEpisode = GRID_WIDTH * GRID_HEIGHT * Config.q_learning.max_steps_per_episode_factor

    actions = { {dx = 0, dy = -1}, {dx = 0, dy = 1}, {dx = 1, dy = 0}, {dx = -1, dy = 0} }

    -- Khởi tạo maze và Q-table lần đầu
    initializeMazeAndQTable()

    -- Thiết lập cửa sổ (kích thước logic)
    local windowWidth = GRID_WIDTH * CELL_SIZE
    local windowHeight = GRID_HEIGHT * CELL_SIZE + 80 -- Thêm không gian cho text
    love.window.setMode(windowWidth, windowHeight) -- Không cần set vsync/resizable nữa nếu đã có trong conf.lua

    print("Q-Learning Maze (Complete Code) Loaded.")
    print("Using config.lua and conf.lua.")
    local scale = 1; if love.window.getPixelScale then scale = love.window.getPixelScale() end -- Kiểm tra trước khi gọi
    print("HiDPI mode:", scale > 1 and "Enabled" or "Disabled/Unsupported", "(Pixel Scale:", scale, ")")
    print("Press 'G' for new maze. Press 'T' to start/resume training.")
end

function love.update(dt)
    if appState == 'training_step' and not isPaused then
        runTrainingSteps(algorithmSpeed)
    elseif appState == 'showing_path' then
        -- Hiện tại không có logic di chuyển agent khi hiển thị path
        -- Chỗ này để trống là đúng cú pháp Lua
    end
end

function love.draw()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)

    -- Vẽ nền ô (Q-Value colors hoặc màu trắng)
    if showQValues and (appState == 'training_step' or appState == 'trained' or appState == 'showing_path') then
        drawQValueColors()
    else
        drawBaseGrid() -- Gọi hàm vẽ nền trắng
    end

    -- Vẽ tường
    drawMazeWalls() -- Gọi hàm vẽ tường

    -- Vẽ đường đi đã học (nếu có)
    if (appState == 'trained' or appState == 'showing_path') and learnedPath and #learnedPath > 0 then
        drawLearnedPath() -- Gọi hàm vẽ đường đi
    end

    -- Vẽ Agent
    drawAgent() -- Gọi hàm vẽ agent

    -- Vẽ điểm bắt đầu/kết thúc
    drawStartEndPoints() -- Gọi hàm vẽ điểm đầu/cuối

    -- Vẽ thông tin
    drawInfoText() -- Gọi hàm vẽ text thông tin
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
     elseif key == 'q' then showQValues = not showQValues
     elseif key == 'h' then showHelp = not showHelp end
     if key == '+' or key == '=' or key == '-' or key == '_' then print("Algorithm Speed set to:", algorithmSpeed) end
end


-- ================================================================
--             INITIALIZATION AND MAZE GENERATION
-- ================================================================

function initializeMazeAndQTable()
    print("Initializing Grid and Q-Table...")
    grid = {}
    qTable = {}
    learnedPath = {}
    currentEpisode = 1 -- Bắt đầu từ episode 1
    currentEpsilon = EPSILON
    agent.x, agent.y = START_X, START_Y
    agent.currentEpisodeSteps = 0
    maxQValueRange = {min = 0, max = 0}
    appState = 'generating_maze' -- Chỉ là trạng thái tạm thời
    isPaused = false

    -- Tạo grid và Q-table rỗng
    for y = 1, GRID_HEIGHT do
        grid[y] = {}
        qTable[y] = {}
        for x = 1, GRID_WIDTH do
            grid[y][x] = {
                x = x, y = y,
                walls = {north = true, south = true, east = true, west = true},
                visited_gen = false,
                color = {0.3, 0.3, 0.3},
                maxQ = 0
            }
            qTable[y][x] = {}
            for i = 1, #actions do qTable[y][x][i] = 0.0 end
        end
    end

    -- Tạo mê cung tức thì
    generateMaze_RecursiveBacktracker_Instant(START_X, START_Y)
    print("Maze generated.")
    appState = 'idle' -- Sẵn sàng để training
end

function generateMaze_RecursiveBacktracker_Instant(startX, startY)
    local stack = {}; local currentCell = grid[startY][startX]; currentCell.visited_gen = true
    local visitedCount = 1; table.insert(stack, currentCell)
    while visitedCount < GRID_WIDTH * GRID_HEIGHT do
        if #stack == 0 then print("Warning: Maze generation stack empty before completion."); break end
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
    -- Reset màu nền sau khi tạo
    for y = 1, GRID_HEIGHT do for x = 1, GRID_WIDTH do grid[y][x].color = {1, 1, 1} end end
end

function removeWall(c1, c2)
    local xd=c1.x-c2.x;local yd=c1.y-c2.y
    if xd==1 then c1.walls.west=false;c2.walls.east=false elseif xd==-1 then c1.walls.east=false;c2.walls.west=false end
    if yd==1 then c1.walls.north=false;c2.walls.south=false elseif yd==-1 then c1.walls.south=false;c2.walls.north=false end
end

-- ================================================================
--                 Q-LEARNING CORE LOGIC
-- ================================================================

function startOrResumeTraining()
    if appState == 'idle' or appState == 'trained' or appState == 'paused' then
        if currentEpisode > NUM_EPISODES then
           print("Training already completed " .. NUM_EPISODES .. " episodes. Press 'G' to reset.")
           -- initializeMazeAndQTable() -- Tùy chọn: reset luôn khi nhấn T sau khi xong
           return -- Không làm gì nếu đã xong và không reset
        end
        appState = 'training_step'
        isPaused = false
        print("Starting/Resuming Training...")
    elseif appState == 'training_step' then
         -- Nếu đang train, nút T sẽ pause/resume (nhưng đã có nút P)
         -- isPaused = not isPaused
         -- print(isPaused and "Training Paused." or "Training Resumed.")
         print("Training is already running. Press 'P' to pause/resume.")
    end
end

function runTrainingSteps(steps)
    if currentEpisode > NUM_EPISODES then
        if appState ~= 'trained' then
            appState = 'trained'
            calculateMaxQValueRange()
            derivePathFromPolicy()
            print("Training finished.")
        end
        return
    end

    for i = 1, steps do
        if currentEpisode > NUM_EPISODES then break end

        -- Bắt đầu episode mới nếu cần
        if agent.x == END_X and agent.y == END_Y or agent.currentEpisodeSteps >= maxStepsPerEpisode then
            currentEpisode = currentEpisode + 1
            if currentEpisode > NUM_EPISODES then break end
            currentEpsilon = math.max(MIN_EPSILON, currentEpsilon * EPSILON_DECAY)
            agent.x, agent.y = START_X, START_Y
            agent.currentEpisodeSteps = 0
            -- In log mỗi 100 episodes chẳng hạn
            if currentEpisode % 100 == 0 then
                print(string.format("Starting Episode: %d / %d (Epsilon: %.4f)", currentEpisode, NUM_EPISODES, currentEpsilon))
            end
        end

        -- Thực hiện 1 bước Q-learning
        local stateX, stateY = agent.x, agent.y
        local actionIndex = chooseAction(stateX, stateY, currentEpsilon)
        local nextX, nextY, reward, isTerminal = takeAction(stateX, stateY, actionIndex)
        updateQValue(stateX, stateY, actionIndex, reward, nextX, nextY) -- Gọi hàm cập nhật riêng
        grid[stateY][stateX].maxQ = getMaxQValue(stateX, stateY) -- Cập nhật maxQ để vẽ
        agent.x, agent.y = nextX, nextY
        agent.currentEpisodeSteps = agent.currentEpisodeSteps + 1
    end

    -- Cập nhật range Q-value thưa hơn
    if love.math.random() < 0.05 then
       calculateMaxQValueRange()
    end
end

-- Hàm cập nhật Q-Value theo công thức Bellman
function updateQValue(sX, sY, actionIdx, reward, nextSX, nextSY)
    local oldQValue = qTable[sY][sX][actionIdx]
    local nextMaxQ = getMaxQValue(nextSX, nextSY)
    local newQValue = oldQValue + LEARNING_RATE * (reward + DISCOUNT_FACTOR * nextMaxQ - oldQValue)
    qTable[sY][sX][actionIdx] = newQValue
end

function chooseAction(stateX, stateY, epsilon)
    if love.math.random() < epsilon then
        return love.math.random(1, #actions) -- Explore
    else
        return getBestAction(stateX, stateY) -- Exploit
    end
end

function takeAction(currentX, currentY, actionIndex)
    local action = actions[actionIndex]; local nextX, nextY = currentX + action.dx, currentY + action.dy
    local reward = REWARD_STEP; local isTerminal = false; local wallHit = false
    -- Kiểm tra tường
    if action.dy == -1 and grid[currentY][currentX].walls.north then wallHit = true end
    if action.dy == 1 and grid[currentY][currentX].walls.south then wallHit = true end
    if action.dx == 1 and grid[currentY][currentX].walls.east then wallHit = true end
    if action.dx == -1 and grid[currentY][currentX].walls.west then wallHit = true end
    -- Kiểm tra biên
    if nextX < 1 or nextX > GRID_WIDTH or nextY < 1 or nextY > GRID_HEIGHT then wallHit = true end

    if wallHit then
        nextX, nextY = currentX, currentY -- Ở yên tại chỗ
        -- reward = reward - 1 -- Có thể phạt thêm khi đâm tường
    end

    -- Kiểm tra đích
    if nextX == END_X and nextY == END_Y then
        reward = REWARD_GOAL
        isTerminal = true
    end
    return nextX, nextY, reward, isTerminal
end

function getMaxQValue(stateX, stateY)
    local maxQ = -math.huge
    -- Đảm bảo state hợp lệ trước khi truy cập qTable
    if qTable and qTable[stateY] and qTable[stateY][stateX] then
        for i = 1, #actions do
            -- Đảm bảo action index hợp lệ
            if qTable[stateY][stateX][i] then
                 maxQ = math.max(maxQ, qTable[stateY][stateX][i])
            else
                 -- print(string.format("Warning: qTable[%d][%d][%d] is nil in getMaxQValue", stateY, stateX, i))
                 -- Có thể gán giá trị mặc định hoặc bỏ qua
                 maxQ = math.max(maxQ, 0) -- Giả sử giá trị mặc định là 0 nếu chưa có
            end
        end
    else
        -- print(string.format("Warning: State (%d, %d) not found in qTable in getMaxQValue", stateX, stateY))
        return 0 -- Trả về 0 nếu state không hợp lệ
    end
     -- Nếu không tìm thấy giá trị nào lớn hơn -inf, trả về 0
    if maxQ == -math.huge then return 0 end
    return maxQ
end

function getBestAction(stateX, stateY)
     local bestAction = 1; local maxQ = -math.huge
     local foundAction = false
     -- Đảm bảo state hợp lệ
     if qTable and qTable[stateY] and qTable[stateY][stateX] then
         for i = 1, #actions do
             -- Đảm bảo action index hợp lệ và giá trị là số
             local currentQ = qTable[stateY][stateX][i]
             if type(currentQ) == "number" then
                 if currentQ > maxQ then
                     maxQ = currentQ
                     bestAction = i
                     foundAction = true
                 end
            -- else print(string.format("Warning: qTable[%d][%d][%d] is not a number in getBestAction", stateY, stateX, i))
             end
         end
     else
         -- print(string.format("Warning: State (%d, %d) not found in qTable in getBestAction", stateX, stateY))
         return love.math.random(1, #actions) -- Hành động ngẫu nhiên nếu state lỗi
     end

     -- Nếu không tìm thấy action nào tốt hơn -inf (ví dụ state chưa khám phá) hoặc tất cả bằng nhau
     if not foundAction then
         return love.math.random(1, #actions)
     end

     -- Kiểm tra xem có nhiều action cùng maxQ không, nếu có thì chọn ngẫu nhiên trong số đó
     local bestActions = {}
     for i = 1, #actions do
        local currentQ = qTable[stateY][stateX][i]
        if type(currentQ) == "number" and math.abs(currentQ - maxQ) < 1e-6 then
            table.insert(bestActions, i)
        end
     end

     if #bestActions > 1 then
         return bestActions[love.math.random(1, #bestActions)] -- Chọn ngẫu nhiên trong các action tốt nhất
     else
         return bestAction -- Chỉ có 1 action tốt nhất
     end
end

function calculateMaxQValueRange()
    maxQValueRange.min = math.huge; maxQValueRange.max = -math.huge
    local foundValue = false
    for y = 1, GRID_HEIGHT do for x = 1, GRID_WIDTH do
        local maxQ = getMaxQValue(x, y); grid[y][x].maxQ = maxQ
        if maxQ > -math.huge then -- Chỉ xét các giá trị hợp lệ
            maxQValueRange.min = math.min(maxQValueRange.min, maxQ)
            maxQValueRange.max = math.max(maxQValueRange.max, maxQ)
            foundValue = true
        end
    end end
    -- Xử lý trường hợp không tìm thấy giá trị nào hoặc min >= max
    if not foundValue or maxQValueRange.min >= maxQValueRange.max then
       maxQValueRange.min = 0
       maxQValueRange.max = 1 -- Đặt một khoảng mặc định
    end
end

function derivePathFromPolicy()
    learnedPath = {}; local currentX, currentY = START_X, START_Y
    local steps = 0; local maxSteps = GRID_WIDTH * GRID_HEIGHT * 1.5 -- Tăng giới hạn một chút
    local pathSet = {}
    while steps < maxSteps do
        local key = currentY .. "," .. currentX
        if pathSet[key] then print("Error deriving path: Loop detected."); learnedPath={}; return; end
        pathSet[key] = true
        table.insert(learnedPath, {x = currentX, y = currentY})
        if currentX == END_X and currentY == END_Y then print("Derived path found. Length:", #learnedPath); return; end
        local bestActionIndex = getBestAction(currentX, currentY)
        -- Kiểm tra action có hợp lệ không (đề phòng lỗi logic)
        if not actions[bestActionIndex] then print("Error deriving path: Invalid best action index."); learnedPath={}; return; end
        local action = actions[bestActionIndex]
        local nextX, nextY = currentX + action.dx, currentY + action.dy
        if nextX < 1 or nextX > GRID_WIDTH or nextY < 1 or nextY > GRID_HEIGHT then print("Error deriving path: Policy leads OOB."); learnedPath={}; return; end
        local wallHit = false
        if action.dy == -1 and grid[currentY][currentX].walls.north then wallHit = true end
        if action.dy == 1 and grid[currentY][currentX].walls.south then wallHit = true end
        if action.dx == 1 and grid[currentY][currentX].walls.east then wallHit = true end
        if action.dx == -1 and grid[currentY][currentX].walls.west then wallHit = true end
        if wallHit then print("Error deriving path: Policy hits wall between ("..currentX..","..currentY..") and ("..nextX..","..nextY..")"); learnedPath={}; return; end
        currentX, currentY = nextX, nextY
        steps = steps + 1
    end
    print("Error deriving path: Max steps reached."); learnedPath = {}
end

-- ================================================================
--                    DRAWING FUNCTIONS
-- ================================================================

function drawBaseGrid()
    love.graphics.setColor(1, 1, 1) -- White
    for y=1,GRID_HEIGHT do for x=1,GRID_WIDTH do
        love.graphics.rectangle("fill", (x-1)*CELL_SIZE, (y-1)*CELL_SIZE, CELL_SIZE, CELL_SIZE)
    end end
end

function drawQValueColors()
    local minQ = maxQValueRange.min
    local maxQ = maxQValueRange.max
    local range = maxQ - minQ
    if range <= 1e-6 then range = 1 end

    for y = 1, GRID_HEIGHT do
        for x = 1, GRID_WIDTH do
            local cell = grid[y][x]
            local normalizedQ = (cell.maxQ - minQ) / range
            normalizedQ = math.max(0, math.min(1, normalizedQ))

            -- Gradient trắng → xanh lam → tím
            local r = 1 - normalizedQ * 0.5
            local g = 1 - normalizedQ * 0.8
            local b = 1

            love.graphics.setColor(r, g, b)
            love.graphics.rectangle("fill", (x-1)*CELL_SIZE, (y-1)*CELL_SIZE, CELL_SIZE, CELL_SIZE)
        end
    end
end

function drawMazeWalls()
    local wallThickness = Config.maze.wall_thickness or 2
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9) -- Darker walls
    love.graphics.setLineWidth(wallThickness)
    for y=1,GRID_HEIGHT do for x=1,GRID_WIDTH do
        local cell = grid[y][x]; local sx=(x-1)*CELL_SIZE; local sy=(y-1)*CELL_SIZE
        if cell.walls.north then love.graphics.line(sx,sy,sx+CELL_SIZE,sy) end
        if cell.walls.south then love.graphics.line(sx,sy+CELL_SIZE,sx+CELL_SIZE,sy+CELL_SIZE) end
        if cell.walls.east then love.graphics.line(sx+CELL_SIZE,sy,sx+CELL_SIZE,sy+CELL_SIZE) end
        if cell.walls.west then love.graphics.line(sx,sy,sx,sy+CELL_SIZE) end
    end end
    love.graphics.setLineWidth(1)
end

function drawLearnedPath()
    if not learnedPath or #learnedPath < 1 then return end
    love.graphics.setColor(1, 1, 0, 0.8) -- Yellow path
    local pathWidthFactor = Config.visualization.path_width_factor or (1/7)
    love.graphics.setLineWidth(math.max(1, CELL_SIZE * pathWidthFactor))
    local points = {}
    for i, cp in ipairs(learnedPath) do
        table.insert(points, (cp.x-0.5)*CELL_SIZE)
        table.insert(points, (cp.y-0.5)*CELL_SIZE)
    end
    if #points >= 4 then love.graphics.line(points) end
    love.graphics.setLineWidth(1)
end

function drawAgent()
     if appState == 'training_step' then
       love.graphics.setColor(1, 0.7, 0, 0.9) -- Orange agent
       local agentSizeFactor = Config.visualization.agent_size_factor or 0.35
       love.graphics.circle("fill", (agent.x - 0.5) * CELL_SIZE, (agent.y - 0.5) * CELL_SIZE, CELL_SIZE * agentSizeFactor)
    end
end

function drawStartEndPoints()
    love.graphics.setColor(0, 1, 0, 0.9) -- Start: Green
    local startScreenX = (START_X - 1) * CELL_SIZE; local startScreenY = (START_Y - 1) * CELL_SIZE
    love.graphics.rectangle("fill", startScreenX + 2, startScreenY + 2, CELL_SIZE - 4, CELL_SIZE - 4)

    love.graphics.setColor(1, 0, 0, 0.9) -- End: Red
    local endScreenX = (END_X - 1) * CELL_SIZE; local endScreenY = (END_Y - 1) * CELL_SIZE
    love.graphics.rectangle("fill", endScreenX + 2, endScreenY + 2, CELL_SIZE - 4, CELL_SIZE - 4)
end

function drawInfoText()
    local yPos = GRID_HEIGHT * CELL_SIZE + 5
    love.graphics.setColor(1, 1, 1) -- White text

    local status = "Status: " .. appState
    if appState == 'training_step' then
        status = string.format("Status: Training (Ep %d/%d, Eps: %.3f) %s", currentEpisode, NUM_EPISODES, currentEpsilon, isPaused and "[PAUSED - P]" or "")
    elseif appState == 'trained' then
        status = "Status: Training Finished (" .. NUM_EPISODES .. " eps)"
    elseif appState == 'showing_path' then
        status = "Status: Showing Learned Path"
    end
     love.graphics.print(status, 10, yPos)

    local speedText = "Speed (Steps/Frame): " .. algorithmSpeed .. " (+/-)"
    love.graphics.print(speedText, 10, yPos + 15)

    local qValueText = "Show Q-Values: " .. (showQValues and "ON" or "OFF") .. " (Q)"
    love.graphics.print(qValueText, 10, yPos + 30)

    if showHelp then
        love.graphics.print("Keys: G=New | T=Train | P=Pause | R=Path", 10, yPos + 45)
        love.graphics.print("+/-=Speed | Q=QVals | H=Help", 10, yPos + 60)
    end
end
