-- Tarantool configs
local listen              = os.getenv("TNT_LISTEN") or 3302
local path                = os.getenv("TNT_PATH") or "/var/lib/tarantool/"
local user                = os.getenv("TNT_USER") or "queue_user"
local pass                = os.getenv("TNT_PASSWORD") or "very_strong_password"
local log_file            = os.getenv("TNT_LOG_FILE") or "/var/log/tarantool/queue.log"
---@type log_level | number
local log_level           = tonumber(os.getenv "TNT_LOG_LEVEL") or 3
local checkpoint_interval = tonumber(os.getenv "TNT_CHECKPOINT_INTERVAL") or (60 * 30)
local vinyl_memory        = tonumber(os.getenv "TNT_VINYL_MEMORY") or (1024 * 1024 * 1024)
local vinyl_cache         = tonumber(os.getenv "TNT_VINYL_CACHE") or (512 * 1024 * 1024)

-- Init Tarantool daemon
box.cfg {
    checkpoint_interval = checkpoint_interval,
    listen              = listen,
    log                 = log_file,
    log_level           = log_level,
    memtx_dir           = path,
    net_msg_max         = 4 * 1024,
    readahead           = 64 * 1024,
    vinyl_dir           = path,
    vinyl_memory        = vinyl_memory,
    vinyl_cache         = vinyl_cache,
    vinyl_write_threads = 4,
    vinyl_read_threads  = 2,
    wal_dir             = path,
}

box.once("schema", function()
    -- Create user
    box.schema.user.create(
        user,
        {
            if_not_exists = true,
            password      = pass,
        }
    )

    -- Grant access
    box.schema.user.grant(user, "read,write,execute", "universe")

    -- Init repeated notifications space
    local space = box.schema.space.create(
        "stored_notifications",
        {
            if_not_exists = true,
            user          = user,
            engine        = "vinyl",
        }
    )

    space:format {
        { name = "user_id",           type = "integer" },
        { name = "task_id",           type = "string"  },
        { name = "remind_text",       type = "string"  },
        { name = "repeat_every",      type = "integer" },
        { name = "repeat_every_type", type = "string"  },
        { name = "year",              type = "integer" },
        { name = "month",             type = "integer" },
        { name = "day",               type = "integer" },
        { name = "hours",             type = "integer" },
        { name = "minutes",           type = "integer" },
        { name = "timezone",          type = "string"  }
    }

    space:create_index(
        'primary',
        {
            if_not_exists = true,
            parts = {
                "user_id",
                "task_id",
            },
        }
    )

    space:create_index(
        'notifications_user_idx',
        {
            if_not_exists = true,
            parts = {
                "user_id",
            },
        }
    )

    -- Init deleted notifications space
    space = box.schema.space.create(
        "deleted_notifications",
        {
            if_not_exists = true,
            user          = user,
            engine        = "vinyl",
        }
    )

    space:format {
        { name = "task_id", type = "string" }
    }

    space:create_index(
        'primary',
        {
            if_not_exists = true,
            parts = {
                "task_id",
            },
        }
    )
end)

queue = require "queue"
queue.create_tube('notifications', 'fifottl', { if_not_exists = true })

-- Add task on_change handler
local datetime = require "datetime"
queue.tube.notifications:on_task_change(
    ---@param notification Notification
    ---@param stats_data stats_data
    function(notification, stats_data)
        if stats_data ~= "ack" then return end
        ---@type StoredNotification | nil
        local stored_notification = box.space.stored_notifications:get{ notification.user_id, notification.task_id }
        if not stored_notification then return end
        ---@type DateTime
        local dt_param = {
            year  = stored_notification.year,
            month = stored_notification.month,
            day   = stored_notification.day,
            hour  = stored_notification.hours,
            min   = stored_notification.minutes,
        }

        ---@type DateTime
        local current_dt = datetime.new(dt_param)
        ---@type TimeInterval
        local interval_param = { adjust = "last" }
        if stored_notification.repeat_every_type == "day" then interval_param.day = stored_notification.repeat_every end
        if stored_notification.repeat_every_type == "week" then interval_param.week = stored_notification.repeat_every end
        if stored_notification.repeat_every_type == "month" then interval_param.month = stored_notification.repeat_every end
        ---@type TimeInterval
        local interval = datetime.interval.new(interval_param)
        ---@type DateTime
        local next_dt = current_dt + interval
        local seconds = os.time(next_dt:totable()) - os.time()
        ---@type StoredNotification
        local new_stored_notification = {
            user_id           = stored_notification.user_id,
            task_id           = stored_notification.task_id,
            remind_text       = stored_notification.remind_text,
            repeat_every      = stored_notification.repeat_every,
            repeat_every_type = stored_notification.repeat_every_type,
            year              = next_dt.year,
            month             = next_dt.month,
            day               = next_dt.day,
            hours             = next_dt.hour,
            minutes           = next_dt.min,
        }

        ---@type Notification
        local notification = {
            user_id     = stored_notification.user_id,
            task_id     = stored_notification.task_id,
            remind_text = stored_notification.remind_text,
        }

        box.space.stored_notifications:replace(new_stored_notification)
        queue.tube.notifications:put(
            notification,
            {
                ttl   = 60,
                delay = seconds,
            }
        )
    end
)
