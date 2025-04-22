-- conf.lua
function love.conf(t)
    t.identity = "q_learning_maze"      -- Tên định danh cho game (dùng cho thư mục save)
    t.version = "11.5"                  -- Phiên bản LÖVE tương thích
    t.console = true                    -- Bật console (hữu ích để debug)

    t.window.title = "Maze Q-Learning" -- Tiêu đề cửa sổ
    t.window.icon = nil                 -- Đường dẫn tới file icon (nếu có)
    t.window.width = 800                -- Chiều rộng cửa sổ ban đầu (sẽ bị ghi đè bởi main.lua dựa trên config)
    t.window.height = 600               -- Chiều cao cửa sổ ban đầu
    t.window.borderless = false
    t.window.resizable = false
    t.window.minwidth = 1
    t.window.minheight = 1
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1                  -- Bật VSync (1=bật, 0=tắt)
    t.window.msaa = 0                   -- Mức khử răng cưa Multi-Sampling Anti-Aliasing
    t.window.display = 1                -- Màn hình hiển thị mặc định (1 là màn hình chính)
    t.window.highdpi = true             -- <<< BẬT HỖ TRỢ HiDPI
    t.window.x = nil                    -- Vị trí cửa sổ X (nil = để hệ điều hành quyết định)
    t.window.y = nil                    -- Vị trí cửa sổ Y

    -- Các modules không dùng đến có thể tắt đi để giảm thời gian load (tùy chọn)
    t.modules.audio = false
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = false
    t.modules.joystick = false -- Tắt nếu không dùng joystick
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false -- Tắt nếu không dùng physics
    t.modules.sound = false
    t.modules.system = true
    t.modules.thread = false -- Tắt nếu không dùng thread
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false -- Tắt nếu không dùng video
    t.modules.window = true
end
