local Log = require("harpoon.logger")
local Ui = require("harpoon.ui")
local Data = require("harpoon.data")
local Config = require("harpoon.config")
local List = require("harpoon.list")
local Extensions = require("harpoon.extensions")
local HarpoonGroup = require("harpoon.autocmd")

---@class Harpoon
---@field config HarpoonConfig
---@field ui HarpoonUI
---@field _extensions HarpoonExtensions
---@field data HarpoonData
---@field logger HarpoonLog
---@field lists {[string]: {[string]: HarpoonList}}
---@field hooks_setup boolean
local Harpoon = {}

Harpoon.__index = Harpoon

---@param harpoon Harpoon
local function sync_on_change(harpoon)
    local function sync(_)
        return function()
            harpoon:sync()
        end
    end

    Extensions.extensions:add_listener({
        ADD = sync("ADD"),
        REMOVE = sync("REMOVE"),
        REORDER = sync("REORDER"),
        LIST_CHANGE = sync("LIST_CHANGE"),
        POSITION_UPDATED = sync("POSITION_UPDATED"),
    })
end

---@return Harpoon
function Harpoon:new()
    local config = Config.get_default_config()

    local harpoon = setmetatable({
        config = config,
        data = Data.Data:new(config),
        logger = Log,
        ui = Ui:new(config.settings),
        _extensions = Extensions.extensions,
        lists = {},
        hooks_setup = false,
    }, self)
    sync_on_change(harpoon)

    Extensions.extensions:add_listener({
        SELECT = function(data)
            harpoon:update_mru(data.item)
        end,
        LIST_CHANGE = function()
            local active_list = harpoon.ui.active_list
            if active_list and active_list.name == "MRU" then
                local key = harpoon.config.settings.key()
                local current_file = require("harpoon.utils").normalize_path(
                    vim.api.nvim_buf_get_name(0),
                    harpoon.config.default.get_root_dir()
                )

                local new_mru = {}
                local old_mru = harpoon.data:data(key, "__mru")

                -- 1. Keep the current file at the top if it was already in MRU
                for _, val in ipairs(old_mru) do
                    local item = harpoon.config.default.decode(val)
                    if item.value == current_file then
                        table.insert(new_mru, val)
                        break
                    end
                end

                -- 2. Add the remaining items from the modified menu
                for _, item in pairs(active_list.items) do
                    if item and item.value then
                        table.insert(new_mru, harpoon.config.default.encode(item))
                    end
                end

                harpoon.data:update(key, "__mru", new_mru)
                harpoon:sync()
            end
        end,
    })

    return harpoon
end

---@param item HarpoonListItem
function Harpoon:update_mru(item)
    if not item or not item.value then
        return
    end
    local key = self.config.settings.key()
    local mru = self.data:data(key, "__mru")
    if type(mru) ~= "table" then
        mru = {}
    end

    -- Remove if exists
    for i, val in ipairs(mru) do
        local decoded = self.config.default.decode(val)
        if decoded.value == item.value then
            table.remove(mru, i)
            break
        end
    end

    -- Prepend (encoded)
    table.insert(mru, 1, self.config.default.encode(item))

    -- Limit size
    while #mru > 20 do
        table.remove(mru)
    end

    self.data:update(key, "__mru", mru)
    self:sync()
end

function Harpoon:toggle_mru_menu(opts)
    local key = self.config.settings.key()
    local mru_data = self.data:data(key, "__mru")
    if type(mru_data) ~= "table" or #mru_data == 0 then
        return
    end

    local current_file = require("harpoon.utils").normalize_path(
        vim.api.nvim_buf_get_name(0),
        self.config.default.get_root_dir()
    )

    local items = {}
    for _, val in ipairs(mru_data) do
        local item = self.config.default.decode(val)
        if item.value ~= current_file then
            table.insert(items, item)
        end
    end

    if #items == 0 then
        return
    end

    local virtual_list = List:new(self.config.default, "MRU", items)
    self.ui:toggle_quick_menu(virtual_list, opts)

    vim.schedule(function()
        if self.ui.win_id and vim.api.nvim_win_is_valid(self.ui.win_id) then
            vim.api.nvim_win_set_cursor(self.ui.win_id, { 1, 0 })
        end
    end)
end

---@param name string?
---@return HarpoonList
function Harpoon:list(name)
    name = name or Config.DEFAULT_LIST

    local key = self.config.settings.key()
    local lists = self.lists[key]

    if not lists then
        lists = {}
        self.lists[key] = lists
    end

    local existing_list = lists[name]

    if existing_list then
        self._extensions:emit(Extensions.event_names.LIST_READ, existing_list)
        return existing_list
    end

    local data = self.data:data(key, name)
    local list_config = Config.get_config(self.config, name)

    local list = List.decode(list_config, name, data)
    self._extensions:emit(Extensions.event_names.LIST_CREATED, list)
    lists[name] = list

    return list
end

---@param cb fun(list: HarpoonList, config: HarpoonPartialConfigItem, name: string)
function Harpoon:_for_each_list(cb)
    local key = self.config.settings.key()
    local lists = self.lists[key]
    if not lists then
        return
    end

    for name, list in pairs(lists) do
        local list_config = Config.get_config(self.config, name)
        cb(list, list_config, name)
    end
end

function Harpoon:sync()
    local key = self.config.settings.key()
    self:_for_each_list(function(list, _, list_name)
        if list.config.encode == false then
            return
        end

        local encoded = list:encode()
        self.data:update(key, list_name, encoded)
    end)
    self.data:sync()
end

--luacheck: ignore 212/self
function Harpoon:info()
    return {
        paths = Data.info(),
        default_list_name = Config.DEFAULT_LIST,
    }
end

--- PLEASE DONT USE THIS OR YOU WILL BE FIRED
function Harpoon:dump()
    return self.data._data
end

---@param extension HarpoonExtension
function Harpoon:extend(extension)
    self._extensions:add_listener(extension)
end

function Harpoon:__debug_reset()
    require("plenary.reload").reload_module("harpoon")
end

local the_harpoon = Harpoon:new()

---@param self Harpoon
---@param partial_config HarpoonPartialConfig?
---@return Harpoon
function Harpoon.setup(self, partial_config)
    if self ~= the_harpoon then
        ---@diagnostic disable-next-line: cast-local-type
        partial_config = self
        self = the_harpoon
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    self.config = Config.merge_config(partial_config, self.config)
    self.data = Data.Data:new(self.config)
    self.ui:configure(self.config.settings)
    self._extensions:emit(Extensions.event_names.SETUP_CALLED, self.config)

    ---TODO: should we go through every seen list and update its config?

    if self.hooks_setup == false then
        vim.api.nvim_create_autocmd({ "BufLeave", "VimLeavePre" }, {
            group = HarpoonGroup,
            pattern = "*",
            callback = function(ev)
                self:_for_each_list(function(list, config)
                    local fn = config[ev.event]
                    if fn ~= nil then
                        fn(ev, list)
                    end

                    if ev.event == "VimLeavePre" then
                        self:sync()
                    end
                end)
            end,
        })

        self.hooks_setup = true
    end

    return self
end

return the_harpoon
