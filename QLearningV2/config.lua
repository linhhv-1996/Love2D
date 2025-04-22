-- config.lua
-- Trả về một bảng chứa các cấu hình cho game mê cung Q-learning

return {
    -- Cấu hình mê cung
    maze = {
        width = 20,             -- Số ô theo chiều ngang
        height = 20,            -- Số ô theo chiều dọc
        cell_size = 25,         -- Kích thước mỗi ô (pixel logic)
        wall_thickness = 1,     -- Độ dày tường vẽ (pixel logic)
    },

    -- Cấu hình Q-learning
    q_learning = {
        episodes = 5000,        -- Số lượt chơi để huấn luyện
        alpha = 0.1,            -- Learning Rate
        gamma = 0.9,            -- Discount Factor
        epsilon_start = 1.0,    -- Epsilon ban đầu
        epsilon_decay = 0.9995, -- Tỷ lệ giảm epsilon
        epsilon_min = 0.01,     -- Epsilon tối thiểu
        max_steps_per_episode_factor = 2, -- Giới hạn bước = width * height * factor
    },

    -- Phần thưởng / Phạt
    rewards = {
        goal = 100,             -- Phần thưởng khi tới đích
        step = -0.1,            -- Phạt cho mỗi bước đi
        wall = -10,             -- (Tùy chọn) Phạt nếu cho phép đâm tường
    },

    -- Cấu hình hiển thị và điều khiển
    visualization = {
        initial_speed = 100,      -- Tốc độ mô phỏng ban đầu (bước/frame)
        show_help_default = true,
        show_q_default = true,
        path_width_factor = 1/5, -- Độ rộng đường đi = cell_size * factor
        agent_size_factor = 0.3, -- Kích thước agent = cell_size * factor
    },

    -- (Tùy chọn) Cấu hình điểm bắt đầu/kết thúc
    -- Nếu không có, main.lua sẽ dùng (1,1) và (width, height)
    -- start_pos = { x = 1, y = 1 },
    -- end_pos = { x = 15, y = 10 },

}
