-- main.lua: Mô phỏng Cháy rừng Nâng cao (Thời gian cháy + Particles)

-- [[ Cài đặt Grid ]]
local gridW, gridH = 50, 30 -- Giảm kích thước chút để đỡ nặng particles
local cellW, cellH
local grid = {}
local nextGrid = {}

-- [[ Trạng thái Ô ]]
-- Bây giờ TREE và BURNING sẽ là table để lưu thêm thông tin
local EMPTY = 0
-- TREE = { state = 1, fuel = F }
-- BURNING = { state = 2, fuel = F, burnTimer = T }
local BURNT = 3
local BURNING = 2
local TREE = 1

-- [[ Tham số Mô phỏng ]]
local initialTreeDensity = 0.70
local ignitionProbability = 0.50 -- Tăng nhẹ xác suất bén lửa
local initialFuel = 100      -- Nhiên liệu ban đầu của cây
local initialBurnTime = 8     -- Số bước một ô cháy (trước khi hết giờ)
local burnRate = initialFuel / initialBurnTime -- Lượng fuel mất mỗi bước để cháy hết sau initialBurnTime
-- Gió
local windDirection = { dx = 0.6, dy = 0.8 } -- Hướng Tây-Nam
local windStrength = 0.8
-- Particles
local particlesPerBurningCell = 3 -- Số hạt sinh ra mỗi bước cho mỗi ô cháy
local particleMaxLife = 1.5     -- Thời gian sống tối đa của hạt (giây)
local gravity = -20            -- Gia tốc trọng trường (âm là bay lên) cho hạt

-- [[ Điều khiển Mô phỏng ]]
local timePerStep = 0.1
local timeSinceLastStep = 0
local stepCount = 0
local running = true

-- [[ Màu sắc ]]
local colors = {
    [EMPTY]   = {139/255, 69/255, 19/255, 1},
    [TREE]    = {34/255, 139/255, 34/255, 1},
    -- BURNING và BURNT sẽ được xử lý đặc biệt trong draw
}

local normalizedWind = {dx=0, dy=0}

-- [[ Hệ thống Hạt ]]
local particles = {} -- Bảng lưu tất cả các hạt đang hoạt động

-- ---------------------------------------------------------------
--                        Hàm Tiện ích
-- ---------------------------------------------------------------
function normalize(v) local len=math.sqrt(v.dx*v.dx+v.dy*v.dy); if len>1e-6 then return{dx=v.dx/len,dy=v.dy/len} else return{dx=0,dy=0} end end
function calculateWindEffect(baseProb,sX,sY,tX,tY) local sV=normalize({dx=tX-sX,dy=tY-sY}); local d=normalizedWind.dx*sV.dx+normalizedWind.dy*sV.dy; local mP=baseProb*(1+windStrength*d*1.5); return math.max(0,math.min(0.98,mP)) end
function isValid(x,y) return x>=1 and x<=gridW and y>=1 and y<=gridH end

-- Hàm tạo hạt mới
function emitParticle(x_cell, y_cell, type)
    local px = (x_cell - 1 + math.random()) * cellW -- Vị trí ngẫu nhiên trong ô
    local py = (y_cell - 1 + math.random()) * cellH
    local life = particleMaxLife * (0.7 + math.random() * 0.6) -- Tuổi thọ ngẫu nhiên chút
    local p = {
        x = px, y = py,
        life = life, maxLife = life,
        type = type,
        vx = 0, vy = 0, -- Vận tốc ban đầu
        size = math.random(2, 4),
        color = {1, 1, 1, 1} -- Màu ban đầu (sẽ cập nhật)
    }

    if type == "flame" then
        -- Lửa bay lên, hơi ngẫu nhiên, ít bị ảnh hưởng bởi gió
        p.vx = (math.random() - 0.5) * 20 + normalizedWind.dx * 5 -- Hơi theo gió
        p.vy = gravity * (0.8 + math.random() * 0.4) -- Bay lên mạnh
        p.color = {1, 0.8 + math.random()*0.2, math.random()*0.3, 0.9} -- Vàng/Cam/Đỏ
        p.size = math.random(3, 6)
    elseif type == "smoke" then
        -- Khói bay lên chậm hơn, bị gió thổi mạnh, màu xám
        p.vx = (math.random() - 0.5) * 10 + normalizedWind.dx * 30 -- Theo gió mạnh
        p.vy = gravity * (0.4 + math.random() * 0.3) + normalizedWind.dy * 10
        local gray = 0.6 + math.random() * 0.4
        p.color = {gray, gray, gray, 0.6}
        p.size = math.random(4, 8)
    end
    table.insert(particles, p)
end

-- Cập nhật trạng thái tất cả hạt
function updateParticles(dt)
    local i = 1
    while i <= #particles do
        local p = particles[i]
        -- Giảm thời gian sống
        p.life = p.life - dt
        -- Xóa nếu hết hạn
        if p.life <= 0 then
            table.remove(particles, i)
            -- Quan trọng: Không tăng i vì phần tử tiếp theo đã dồn lên vị trí i
        else
            -- Cập nhật vận tốc (gió, trọng lực ảo)
            p.vx = p.vx + (normalizedWind.dx * 40 - p.vx * 0.1) * dt -- Gió đẩy + Giảm tốc nhẹ
            p.vy = p.vy + (gravity + normalizedWind.dy * 20 - p.vy * 0.1) * dt -- Trọng lực ảo + Gió + Giảm tốc

            -- Cập nhật vị trí
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt

            -- Cập nhật hình ảnh (màu sắc, kích thước) dựa trên tuổi thọ còn lại
            local lifeRatio = p.life / p.maxLife
            if p.type == "flame" then
                -- Lửa mờ dần và đỏ hơn khi sắp tắt
                p.color[1] = 1 -- Giữ đỏ
                p.color[2] = 0.2 + 0.8 * lifeRatio -- Bớt vàng
                p.color[3] = 0.1
                p.color[4] = 0.2 + 0.7 * lifeRatio * lifeRatio -- Mờ nhanh hơn lúc cuối
                p.size = math.max(1, p.size * lifeRatio)
            elseif p.type == "smoke" then
                -- Khói mờ dần
                p.color[4] = 0.1 + 0.5 * lifeRatio * lifeRatio
                -- Có thể làm khói tan bự ra rồi nhỏ lại
                -- p.size = p.size * (1 + (1-lifeRatio)*0.1)
            end
            i = i + 1 -- Chuyển sang hạt tiếp theo
        end
    end
end

-- ---------------------------------------------------------------
--                     Logic Mô phỏng Chính
-- ---------------------------------------------------------------
function runSimulationStep()
    stepCount = stepCount + 1
    for x = 1, gridW do
        if not nextGrid[x] then nextGrid[x] = {} end
        for y = 1, gridH do
            local currentCell = grid[x][y]
            local currentState = EMPTY
            if type(currentCell) == 'table' then
                currentState = currentCell.state
            elseif currentCell == BURNT then -- BURNT vẫn là số
                currentState = BURNT
            end

            local nextStateInfo = currentCell -- Mặc định giữ nguyên (quan trọng khi copy table)

            if currentState == 2 then -- BURNING
                local remainingFuel = currentCell.fuel - burnRate
                local remainingTime = currentCell.burnTimer - 1

                -- Sinh hạt lửa và khói
                for i=1, particlesPerBurningCell do emitParticle(x, y, "flame") end
                if math.random() < 0.5 then -- Sinh khói ít hơn
                     for i=1, particlesPerBurningCell-1 do emitParticle(x, y, "smoke") end
                end

                -- Kiểm tra hết nhiên liệu hoặc hết giờ cháy
                if remainingFuel <= 0 or remainingTime <= 0 then
                    nextStateInfo = BURNT -- Chuyển thành đã cháy
                    -- Sinh ít khói cuối cùng
                     if math.random() < 0.8 then emitParticle(x, y, "smoke") end
                else
                    -- Vẫn đang cháy, cập nhật lại fuel và timer
                    -- Tạo bản sao để không ảnh hưởng grid cũ khi tính toán neighbor
                     nextStateInfo = {
                         state = 2,
                         fuel = remainingFuel,
                         burnTimer = remainingTime
                     }
                end

            elseif currentState == 1 then -- TREE
                local catchesFire = false
                for dx = -1, 1 do for dy = -1, 1 do if dx~=0 or dy~=0 then
                    local nx, ny = x+dx, y+dy
                    if isValid(nx,ny) and grid[nx][ny] and type(grid[nx][ny])=='table' and grid[nx][ny].state == 2 then -- Kiểm tra hàng xóm là BURNING
                        local spreadProb = calculateWindEffect(ignitionProbability, nx,ny, x,y)
                        -- Yếu tố fuel của cây hiện tại có thể ảnh hưởng? (ví dụ)
                        -- spreadProb = spreadProb * (currentCell.fuel / initialFuel * 0.5 + 0.5)
                        if math.random() < spreadProb then
                            catchesFire = true; goto check_done
                        end
                    end
                end end ::check_done::

                if catchesFire then
                     -- Bén lửa! Khởi tạo trạng thái cháy
                     nextStateInfo = {
                         state = 2,
                         fuel = currentCell.fuel, -- Giữ nguyên fuel của cây
                         burnTimer = initialBurnTime -- Bắt đầu đếm giờ cháy
                     }
                     -- Sinh ít lửa/khói ngay khi bén
                     emitParticle(x, y, "flame")
                     if math.random() < 0.3 then emitParticle(x, y, "smoke") end
                -- else -- Vẫn là cây (đã mặc định)
                end
            -- else -- EMPTY hoặc BURNT thì giữ nguyên (đã mặc định)
            end
            nextGrid[x][y] = nextStateInfo
        end
    end
    -- Cập nhật grid chính (phải copy cẩn thận vì có table)
    for x=1, gridW do
        if not grid[x] then grid[x] = {} end
        for y=1, gridH do
            if type(nextGrid[x][y]) == 'table' then
                 -- Sao chép table để grid và nextGrid độc lập
                 grid[x][y] = {
                     state = nextGrid[x][y].state,
                     fuel = nextGrid[x][y].fuel,
                     burnTimer = nextGrid[x][y].burnTimer
                 }
             else
                 grid[x][y] = nextGrid[x][y] -- Gán giá trị số (EMPTY, BURNT)
             end
        end
    end
    end
end
-- ---------------------------------------------------------------
--                        Love2D Callbacks
-- ---------------------------------------------------------------
function love.load()
    math.randomseed(os.time())
    W, H = love.graphics.getDimensions()
    cellW = W / gridW
    cellH = H / gridH
    normalizedWind = normalize(windDirection)
    particles = {} -- Reset particles khi load

    for x=1, gridW do
        grid[x] = {}
        nextGrid[x] = {}
        for y=1, gridH do
            if math.random() < initialTreeDensity then
                grid[x][y] = { state = 1, fuel = initialFuel * (0.8 + math.random()*0.4) } -- Fuel ngẫu nhiên chút
            else
                grid[x][y] = EMPTY
            end
            -- Sao chép trạng thái ban đầu cho nextGrid (quan trọng với table)
            if type(grid[x][y]) == 'table' then
                 nextGrid[x][y] = { state = grid[x][y].state, fuel = grid[x][y].fuel }
            else
                 nextGrid[x][y] = grid[x][y]
            end
        end
    end
    -- Châm lửa
    local startFireCol = 2
    for y=1, gridH do
        if grid[startFireCol] and type(grid[startFireCol][y])=='table' and grid[startFireCol][y].state == 1 then
             grid[startFireCol][y] = { state = 2, fuel = grid[startFireCol][y].fuel, burnTimer = initialBurnTime }
             nextGrid[startFireCol][y] = { state = 2, fuel = grid[startFireCol][y].fuel, burnTimer = initialBurnTime }
        end
        if grid[1] and type(grid[1][y])=='table' and grid[1][y].state == 1 then
             grid[1][y] = { state = 2, fuel = grid[1][y].fuel, burnTimer = initialBurnTime }
             nextGrid[1][y] = { state = 2, fuel = grid[1][y].fuel, burnTimer = initialBurnTime }
        end
    end
    love.window.setTitle("Forest Fire Sim v2 (Particles + Burn Time)")
end

function love.update(dt)
    updateParticles(dt) -- Cập nhật tất cả hạt trước
    if not running then return end
    timeSinceLastStep = timeSinceLastStep + dt
    while timeSinceLastStep >= timePerStep do
        runSimulationStep()
        timeSinceLastStep = timeSinceLastStep - timePerStep
    end
end

function love.draw()
    local treeC, burningC, burntC = 0,0,0
    -- 1. Vẽ Grid trước
    for x = 1, gridW do
        for y = 1, gridH do
            local cell = grid[x][y]
            local state = EMPTY
            local fuelRatio = 1.0
            local burnRatio = 1.0
            if type(cell) == 'table' then
                 state = cell.state
                 if state == 1 then fuelRatio = cell.fuel / initialFuel end
                 if state == 2 then burnRatio = cell.burnTimer / initialBurnTime end
            elseif cell == BURNT then
                 state = BURNT
            end

            local drawX = (x-1)*cellW
            local drawY = (y-1)*cellH
            local clr

            if state == EMPTY then clr = colors[EMPTY]
            elseif state == 1 then -- TREE
                clr = colors[TREE]
                -- Làm màu xanh đậm hơn nếu fuel ít hơn (ví dụ)
                love.graphics.setColor(clr[1]*0.7 + clr[1]*0.3*fuelRatio, clr[2]*0.7 + clr[2]*0.3*fuelRatio, clr[3], clr[4])
                treeC=treeC+1
            elseif state == 2 then -- BURNING
                -- Màu thay đổi dựa trên thời gian cháy còn lại
                local baseR, baseG, baseB = 1, 0.4, 0 -- Cam đỏ gốc
                -- Chuyển dần sang đỏ sẫm / cam tối khi sắp tắt
                local intensity = 0.5 + 0.5 * burnRatio -- Sáng hơn khi mới cháy
                love.graphics.setColor(baseR * intensity, baseG * intensity * 0.8, baseB, 1)
                burningC=burningC+1
            elseif state == 3 then -- BURNT
                clr = colors[BURNT]
                love.graphics.setColor(clr[1], clr[2], clr[3], clr[4])
                burntC=burntC+1
            end
            love.graphics.rectangle("fill", drawX, drawY, cellW, cellH)
        end
    end

    -- 2. Vẽ Particles đè lên trên Grid
    love.graphics.setPointSize(1) -- Reset size phòng khi thay đổi
    for _, p in ipairs(particles) do
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], p.color[4])
        love.graphics.setPointSize(p.size)
        love.graphics.points(p.x, p.y)
    end
    love.graphics.setPointSize(1) -- Reset về mặc định

    -- 3. Vẽ Thông tin & Gió (như cũ)
    love.graphics.setColor(0,0,0,0.6); love.graphics.rectangle("fill", 0, 0, W, 25)
    love.graphics.setColor(1,1,1);
    local statusText = string.format("Step:%d|Tree:%d|Burning:%d|Burnt:%d|Particles:%d|Running:%s", stepCount, treeC, burningC, burntC, #particles, tostring(running))
    love.graphics.print(statusText, 5, 5)
    -- Vẽ gió
    local windX, windY = W-50, 12; love.graphics.print("Wind:", W-95, 5)
    love.graphics.setLineWidth(2); love.graphics.setColor(0.8,0.8,1,0.8)
    love.graphics.line(windX, windY, windX+normalizedWind.dx*25, windY+normalizedWind.dy*25)
    local angle=math.atan2(normalizedWind.dy,normalizedWind.dx); local aX1=windX+normalizedWind.dx*25-math.cos(angle-math.pi/6)*8; local aY1=windY+normalizedWind.dy*25-math.sin(angle-math.pi/6)*8; local aX2=windX+normalizedWind.dx*25-math.cos(angle+math.pi/6)*8; local aY2=windY+normalizedWind.dy*25-math.sin(angle+math.pi/6)*8; love.graphics.line(windX+normalizedWind.dx*25,windY+normalizedWind.dy*25, aX1, aY1); love.graphics.line(windX+normalizedWind.dx*25,windY+normalizedWind.dy*25, aX2, aY2); love.graphics.setLineWidth(1)
end

function love.keypressed(key)
    if key == 'p' then running = not running
    elseif key == 'r' then love.load(); running=true; timeSinceLastStep=0; stepCount=0;
    end
end

function love.mousepressed(mx, my, button)
    if button == 1 then
        local gx, gy = math.floor(mx/cellW)+1, math.floor(my/cellH)+1
        if isValid(gx, gy) and grid[gx][gy] and type(grid[gx][gy])=='table' and grid[gx][gy].state == 1 then
             local fuel = grid[gx][gy].fuel -- Giữ fuel của cây đó
             grid[gx][gy] = { state=2, fuel=fuel, burnTimer=initialBurnTime }
             -- Cập nhật cả nextGrid để tránh lỗi logic nếu click khi đang chạy step
             nextGrid[gx][gy] = { state=2, fuel=fuel, burnTimer=initialBurnTime }
             print("Đã châm lửa ô:", gx, gy)
        end
    end
end