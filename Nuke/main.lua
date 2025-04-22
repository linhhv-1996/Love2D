-- main.lua: Julia Set visualization with step-by-step animation

local imageData, image
local iterationData = nil -- 2D table storing the iteration count 'n' for each pixel
local W, H
local gameState = "loading" -- States: loading, calculating, animating, done, error
local calcCoroutine = nil
local calcProgress = 0

-- [[ Fractal Parameters ]]
local maxIterations = 200
local escapeRadius = 4.0
local escapeRadiusSq = escapeRadius * escapeRadius
local C = { x = -0.75, y = 0.11 }
local view = { xmin = -1.6, xmax = 1.6, ymin = -1.0, ymax = 1.0 }
local palette = {}

-- [[ Animation Parameters ]]
local currentMaxIterationShown = 0 -- Current iteration threshold being animated
local animationSpeed = 10 -- Iterations revealed per second

-- Utility: Linear map function
function map(value, from1, to1, from2, to2)
    if from1 == to1 then return from2 end
    return from2 + (value - from1) * (to2 - from2) / (to1 - from1)
end

-- Generate a cubehelix-inspired color palette with brightness boost
function generatePalette(size)
    local pal = {}
    local baseBrightness = 0.15 -- Lift brightness
    for i = 0, size - 1 do
        local t = i / (size - 1)
        local angle = 2 * math.pi * (0.5 + 1.5 * t)
        local amp = 0.5 * t * (1 - t)
        local r = t + amp * (-0.14861 * math.cos(angle) + 1.78277 * math.sin(angle))
        local g = t + amp * (-0.29227 * math.cos(angle) - 0.90649 * math.sin(angle))
        local b = t + amp * (1.97294 * math.cos(angle))
        table.insert(pal, {
            math.min(1, r + baseBrightness),
            math.min(1, g + baseBrightness),
            math.min(1, b + baseBrightness),
            1
        })
    end
    return pal
end

-- Calculate and store iteration count 'n' for each pixel
function calculateIterationData()
    print("Starting iteration data calculation...")
    local startTime = love.timer.getTime()
    iterationData = {} -- Reset previous data

    for px = 0, W - 1 do -- Iterate column-wise for better coroutine yielding
        iterationData[px] = {}
        for py = 0, H - 1 do
            -- Map pixel to complex plane
            local zx = map(px, 0, W - 1, view.xmin, view.xmax)
            local zy = map(py, 0, H - 1, view.ymax, view.ymin)

            local n = 0
            -- Julia iteration loop
            while n < maxIterations do
                if zx * zx + zy * zy > escapeRadiusSq then break end
                local xtemp = zx * zx - zy * zy + C.x
                zy = 2 * zx * zy + C.y
                zx = xtemp
                n = n + 1
            end
            iterationData[px][py] = n
        end
        -- Update progress and yield every few columns
        calcProgress = (px + 1) / W
        if px % 5 == 0 then
            coroutine.yield()
        end
    end

    local endTime = love.timer.getTime()
    print(string.format("Calculation complete in %.2f seconds.", endTime - startTime))
    return "calculated"
end

-- Update imageData for the current animation step
function updateImageDataForAnimation()
    if not iterationData then return end

    imageData:mapPixel(function(px, py, r, g, b, a)
        local n = iterationData[px][py]

        -- Background color for pixels not yet animated
        local bg_r, bg_g, bg_b, bg_a = 0.02, 0.0, 0.07, 1

        if n < currentMaxIterationShown then
            -- Escaped within current shown iterations → color using palette
            local colorIndex = (n % #palette) + 1
            local clr = palette[colorIndex]
            if clr then return clr[1], clr[2], clr[3], clr[4]
            else return bg_r, bg_g, bg_b, bg_a end
        elseif n == maxIterations and currentMaxIterationShown >= maxIterations then
            -- Belongs to the Julia set → color black
            return 0, 0, 0, 1
        else
            -- Not yet animated or still in bounds → show background
            return bg_r, bg_g, bg_b, bg_a
        end
    end)
    image:replacePixels(imageData)
end

function love.load()
    W, H = 500, 500
    love.window.setMode(W, H, {resizable=false})
    love.window.setTitle("Julia Set Animation (C = " .. C.x .. " + " .. C.y .. "i)")

    imageData = love.image.newImageData(W, H)
    image = love.graphics.newImage(imageData)
    palette = generatePalette(150)

    -- Start coroutine for data calculation
    gameState = "calculating"
    calcCoroutine = coroutine.create(calculateIterationData)
    calcProgress = 0
    local ok, err = coroutine.resume(calcCoroutine)
    if not ok then print("Coroutine error:", err); gameState = "error"; end
end

function love.update(dt)
    if gameState == "calculating" then
        -- Continue coroutine step-by-step
        if calcCoroutine and coroutine.status(calcCoroutine) == "suspended" then
            local ok, err = coroutine.resume(calcCoroutine)
            if not ok then print("Coroutine error:", err); gameState = "error"; end
        elseif coroutine.status(calcCoroutine) ~= "suspended" then
            if coroutine.status(calcCoroutine) == "dead" and iterationData then
                gameState = "animating"
                currentMaxIterationShown = 0
                updateImageDataForAnimation()
                print("Data ready. Starting animation.")
            else
                print("Error or coroutine did not complete properly.")
                gameState = "error"
            end
        end
    elseif gameState == "animating" then
        -- Advance animation
        if currentMaxIterationShown < maxIterations then
            currentMaxIterationShown = currentMaxIterationShown + animationSpeed * dt
            updateImageDataForAnimation()
        else
            currentMaxIterationShown = maxIterations
            updateImageDataForAnimation()
            gameState = "done"
            print("Animation finished.")
        end
    end
end

function love.draw()
    -- Draw the image to the screen
    love.graphics.draw(image, 0, 0)

    -- Draw status text
    love.graphics.setColor(1, 1, 1)
    if gameState == "calculating" then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 10, H - 40, W - 20, 30)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Calculating data... %.0f%%", calcProgress * 100), 20, H - 35)
    elseif gameState == "animating" then
        love.graphics.print(string.format("Animating: showing iterations < %.0f / %d (Press R to replay)", currentMaxIterationShown, maxIterations), 10, 10)
    elseif gameState == "done" then
        love.graphics.print("Animation complete. Press R to replay.", 10, 10)
    elseif gameState == "error" then
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("An error occurred.", 10, 10)
    end
end

function love.keypressed(key)
    -- Press 'R' to replay the animation (without recalculating)
    if key == 'r' and (gameState == "animating" or gameState == "done") and iterationData then
        print("Replaying animation.")
        gameState = "animating"
        currentMaxIterationShown = 0
        updateImageDataForAnimation()
    end
    -- Optional: press Space to recalculate (e.g., after changing C)
    -- if key == "space" and not calculating then ...
end
