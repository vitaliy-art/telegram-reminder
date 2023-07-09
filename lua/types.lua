---@alias log_level
---| '1' # SYSERROR
---| '2' # ERROR
---| '3' # CRITICAL
---| '4' # WARNING
---| '5' # INFO
---| '6' # VERBOSE
---| '7' # DEBUG

---@alias repeat_every_type '"day"' | '"week"' | '"month"'

---@class StoredNotification
---@field user_id           integer
---@field task_id           string
---@field remind_text       string
---@field repeat_every      integer
---@field repeat_every_type repeat_every_type
---@field year              integer
---@field month             integer
---@field day               integer
---@field hours             integer
---@field minutes           integer
---@field timezone          string

---@class Notification
---@field user_id     integer
---@field task_id     string
---@field remind_text string

---@alias stats_data '"ack"' | '"take"' | '"kick"' | '"bury"' | '"put"' | '"delete"'

---@class DateTime
---@field sec   integer
---@field min   integer
---@field hour  integer
---@field day   integer
---@field month integer
---@field year  integer
---@field totable fun(self: DateTime): table

---@alias adjust_type '"none"' | '"last"' | '"excess"'

---@class TimeInterval
---@field year   integer
---@field month  integer
---@field week   integer
---@field day    integer
---@field hour   integer
---@field min    integer
---@field adjust adjust_type
