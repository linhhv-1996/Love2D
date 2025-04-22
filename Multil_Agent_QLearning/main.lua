-- main.lua: Joint Action Q-Learning - 3 Agent tìm đường trong Mê cung

-- [[ Cài đặt Grid & Agents ]]
local gridW, gridH = 9, 9 -- Kích thước lưới lớn hơn cho mê cung
local cellW, cellH
local numAgents = 3
local agents = {}
local mazeGrid = {} -- Lưu cấu trúc mê cung: 0 = path, 1 = wall
local exitPos = { x = gridW, y = gridH } -- Ví dụ: Lối ra ở góc dưới phải

-- [[ Tham số Q-Learning ]]
local alpha = 0.1
local gamma = 0.9
local epsilon = 1.0
local epsilonDecay = 0.9998 -- Giảm epsilon chậm hơn chút vì không gian lớn hơn
local minEpsilon = 0.05
local Q_table = {}

-- [[ Hành động ]]
local actions = { {dx=0, dy=-1}, {dx=0, dy=1}, {dx=-1, dy=0}, {dx=1, dy=0}, {dx=0, dy=0} }
local numActionsPerAgent = #actions
local numJointActions = numActionsPerAgent ^ numAgents -- 5^3 = 125

-- [[ Điều khiển Mô phỏng & Học ]]
local timePerStep = 0.03 -- Tăng tốc độ mô phỏng chút
local timeSinceLastStep = 0
local episode = 0
local step = 0
local maxStepsPerEpisode = 150 -- Tăng số bước tối đa
local stepsPerFrame = 10    -- Chạy nhiều bước logic mỗi frame

-- ---------------------------------------------------------------
--                        Maze Generation (Recursive Backtracker)
-- ---------------------------------------------------------------
function generateMaze(width, height)
    local maze = {}
    local visited = {}
    -- Khởi tạo lưới toàn tường và chưa thăm
    for x = 1, width do
        maze[x] = {}
        visited[x] = {}
        for y = 1, height do
            maze[x][y] = 1 -- 1 = Wall
            visited[x][y] = false
        end
    end

    local stack = {}
    -- Bắt đầu từ ô (1, 1) - phải là đường đi
    local currentX, currentY = 1, 1
    maze[currentX][currentY] = 0 -- 0 = Path
    visited[currentX][currentY] = true
    table.insert(stack, {x=currentX, y=currentY})

    while #stack > 0 do
        currentX = stack[#stack].x
        currentY = stack[#stack].y

        -- Tìm hàng xóm chưa thăm (cách 2 ô để tạo đường đi)
        local neighbors = {}
        local potentialNeighbors = {
            {dx=0, dy=-2}, {dx=0, dy=2}, {dx=-2, dy=0}, {dx=2, dy=0}
        }
        for _, dir in ipairs(potentialNeighbors) do
            local nx, ny = currentX + dir.dx, currentY + dir.dy
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height and not visited[nx][ny] then
                table.insert(neighbors, {x=nx, y=ny, dx=dir.dx, dy=dir.dy})
            end
        end

        if #neighbors > 0 then
            -- Chọn ngẫu nhiên một hàng xóm
            local chosen = neighbors[math.random(#neighbors)]
            local nx, ny = chosen.x, chosen.y
            local dx, dy = chosen.dx, chosen.dy

            -- Đục tường giữa ô hiện tại và ô hàng xóm
            maze[currentX + dx/2][currentY + dy/2] = 0 -- Path

            -- Đánh dấu ô hàng xóm là đã thăm và đặt làm ô hiện tại
            maze[nx][ny] = 0 -- Path
            visited[nx][ny] = true
            table.insert(stack, {x=nx, y=ny}) -- Đưa ô mới vào stack
        else
            -- Không còn hàng xóm chưa thăm -> backtrack
            table.remove(stack)
        end
    end
    return maze
end

-- ---------------------------------------------------------------
--                        Hàm Tiện ích (JAQL)
-- ---------------------------------------------------------------
-- getStateString, decodeJointAction, getQValue, getMaxQ, chooseJointAction, updateQValue (Giữ nguyên như trước)
function getStateString(agentPositions) local p={}; for i=1,numAgents do table.insert(p,agentPositions[i].x..","..agentPositions[i].y) end; return table.concat(p,"_") end
function decodeJointAction(j) local a={}; local t=j-1; a[3]=(t%numActionsPerAgent)+1; t=math.floor(t/numActionsPerAgent); a[2]=(t%numActionsPerAgent)+1; t=math.floor(t/numActionsPerAgent); a[1]=(t%numActionsPerAgent)+1; return a end
function getQValue(s, j) if Q_table[s] and Q_table[s][j] then return Q_table[s][j] else return 0.0 end end
function getMaxQ(s) local maxQ=-math.huge; local bestA=1; local nT=0; if not Q_table[s] then Q_table[s]={} end; for j=1,numJointActions do local q=getQValue(s,j); if q>maxQ then maxQ=q; bestA=j; nT=1 elseif q==maxQ then nT=nT+1; if math.random(nT)==1 then bestA=j end end end; if maxQ==-math.huge then maxQ=0.0 end; return bestA, maxQ end
function chooseJointAction(s, e) if math.random()<e then return math.random(numJointActions) else local bestA,_ = getMaxQ(s); return bestA end end
function updateQValue(s, j, r, s_prime) local _, maxQ_p = getMaxQ(s_prime); local oldQ = getQValue(s, j); local newQ = oldQ + alpha * (r + gamma * maxQ_p - oldQ); if not Q_table[s] then Q_table[s] = {} end; Q_table[s][j] = newQ end

-- Áp dụng hành động, *có kiểm tra tường*
function applyActions(currentAgents, agentActions)
    local nextAgents = {}
    for i = 1, numAgents do
        local currentPos = currentAgents[i]
        local actionIdx = agentActions[i]
        local move = actions[actionIdx]
        local nextX = currentPos.x + move.dx
        local nextY = currentPos.y + move.dy

        -- Kiểm tra biên VÀ tường
        if nextX < 1 or nextX > gridW or nextY < 1 or nextY > gridH or mazeGrid[nextX][nextY] == 1 then
            nextX = currentPos.x -- Không di chuyển nếu ra biên hoặc vào tường
            nextY = currentPos.y
        end
        -- Lưu ý: Vẫn chưa xử lý va chạm agent-agent
        table.insert(nextAgents, {x = nextX, y = nextY})
    end
    return nextAgents
end

-- Tính phần thưởng - Mục tiêu: Cả 3 agent cùng đến ô exitPos
function getReward(nextAgentPositions)
    local allAgentsOnTarget = true
    for i = 1, numAgents do
        if nextAgentPositions[i].x ~= exitPos.x or nextAgentPositions[i].y ~= exitPos.y then
            allAgentsOnTarget = false
            break
        end
    end

    if allAgentsOnTarget then
        return 10.0 -- Thưởng lớn
    else
        return -0.1 -- Phạt nhỏ mỗi bước
    end
end

-- Reset agent về vị trí đường đi ngẫu nhiên, không trùng nhau, không ở ô đích
function resetAgents()
    local usedPositions = {}
    agents = {} -- Xóa vị trí cũ
    -- Đánh dấu ô đích là đã dùng để không đặt agent vào đó
    usedPositions[exitPos.x .. "," .. exitPos.y] = true

    for i = 1, numAgents do
        local x, y
        repeat
            x = math.random(gridW)
            y = math.random(gridH)
        -- Tìm ô đường đi (==0), chưa có agent khác, và không phải ô đích
        until mazeGrid[x][y] == 0 and not usedPositions[x .. "," .. y]
        agents[i] = {x = x, y = y}
        usedPositions[x .. "," .. y] = true -- Đánh dấu ô này đã có agent
    end
end

-- Chạy một bước logic Q-learning (Giữ nguyên logic cốt lõi)
function runLearningStep()
    local currentStateString = getStateString(agents)
    local jointAction = chooseJointAction(currentStateString, epsilon)
    local agentActions = decodeJointAction(jointAction)

    local nextAgentPositions = applyActions(agents, agentActions)
    local reward = getReward(nextAgentPositions)
    local nextStateString = getStateString(nextAgentPositions)

    updateQValue(currentStateString, jointAction, reward, nextStateString)

    agents = nextAgentPositions
    step = step + 1

    local allOnTarget = true
    for i = 1, numAgents do if agents[i].x ~= exitPos.x or agents[i].y ~= exitPos.y then allOnTarget = false; break end end

    if step >= maxStepsPerEpisode or allOnTarget then
        episode = episode + 1
        step = 0
        epsilon = math.max(minEpsilon, epsilon * epsilonDecay)
        -- Chỉ in mỗi 100 episodes cho đỡ rối console
        if episode % 100 == 0 then
             print("Starting Episode:", episode, "Epsilon:", epsilon, "Q-table size:", #Q_table)
        end
        resetAgents()
    end
end

-- ---------------------------------------------------------------
--                        Love2D Callbacks
-- ---------------------------------------------------------------

function love.load()
    W, H = love.graphics.getDimensions()
    cellW = W / gridW
    cellH = H / gridH
    math.randomseed(os.time())

    -- Tạo mê cung
    mazeGrid = generateMaze(gridW, gridH)
    -- Đảm bảo ô đích là đường đi (có thể thuật toán maze không đảm bảo góc)
    mazeGrid[exitPos.x][exitPos.y] = 0
    -- Đảm bảo ô (1,1) là đường đi để có thể bắt đầu
    mazeGrid[1][1] = 0


    -- Reset agent lần đầu
    resetAgents()

    love.window.setTitle("3-Agent JAQL Maze Solver (9x9)")
end

function love.update(dt)
    for i = 1, stepsPerFrame do
        runLearningStep()
    end
end

function love.draw()
    -- Vẽ nền trắng
    love.graphics.setBackgroundColor(1, 1, 1)

    -- Vẽ mê cung
    for x = 1, gridW do
        for y = 1, gridH do
            if mazeGrid[x][y] == 1 then -- Wall
                love.graphics.setColor(0.2, 0.2, 0.2) -- Màu tường tối
            else -- Path
                 love.graphics.setColor(0.95, 0.95, 0.95) -- Màu đường đi sáng
            end
            love.graphics.rectangle("fill", (x - 1) * cellW, (y - 1) * cellH, cellW, cellH)
        end
    end

    -- Vẽ ô đích (lối ra)
    love.graphics.setColor(0.1, 0.8, 0.1, 0.9) -- Màu xanh lá cây
    love.graphics.rectangle("fill", (exitPos.x - 1) * cellW, (exitPos.y - 1) * cellH, cellW, cellH)

    -- Vẽ agents (hình tròn)
    local agentColors = {{1, 0.2, 0.2}, {0.2, 1, 0.2}, {0.2, 0.2, 1}} -- Đỏ, Lục, Lam
    local agentRadius = math.min(cellW, cellH) * 0.35 -- Bán kính hình tròn agent

    for i = 1, numAgents do
        love.graphics.setColor(agentColors[i])
        local ax, ay = agents[i].x, agents[i].y
        -- Tính tọa độ tâm hình tròn
        local drawX = (ax - 0.5) * cellW
        local drawY = (ay - 0.5) * cellH
        love.graphics.circle("fill", drawX, drawY, agentRadius)
    end

    -- Hiển thị thông tin
    love.graphics.setColor(0,0,0,0.7)
    love.graphics.rectangle("fill", 0, H-20, W, 20)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("Episode: %d | Step: %d | Epsilon: %.4f | Q-Entries: %d", episode, step, epsilon, #Q_table), 5, H - 18)
end
