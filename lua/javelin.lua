return { -- ============= Harpoon ===========
  'ThePrimeagen/harpoon',
  branch = 'harpoon2',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local harpoon = require 'harpoon'
    harpoon:setup()
    -- Add built-in extension for highlighting current file
    local harpoon_extensions = require 'harpoon.extensions'
    harpoon:extend(harpoon_extensions.builtins.highlight_current_file())

    local ok, wk = pcall(require, 'which-key')
    if ok then
      wk.add {
        { '<leader>v', group = 'harpoon' },
      }
    end
    vim.keymap.set('n', '<leader>vc', function()
      harpoon:list():add()
    end, { desc = 'harpoon add to list' })

    vim.keymap.set('n', '<leader>vv', function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end, { desc = 'harpoon show menu' })

    vim.keymap.set('n', '<leader>v1', function()
      harpoon:list():select(1)
    end, { desc = 'harpoon to 1' })
    vim.keymap.set('n', '<leader>v2', function()
      harpoon:list():select(2)
    end, { desc = 'harpoon to 2' })
    vim.keymap.set('n', '<leader>v3', function()
      harpoon:list():select(3)
    end, { desc = 'harpoon to 3' })
    vim.keymap.set('n', '<leader>v4', function()
      harpoon:list():select(4)
    end, { desc = 'harpoon to 4' })

    -- Toggle previous & next buffers stored within Harpoon list
    vim.keymap.set('n', '<leader>v,', function()
      harpoon:list():prev()
    end, { desc = 'harpoon prev' })
    vim.keymap.set('n', '<leader>v.', function()
      harpoon:list():next()
    end, { desc = 'harpoon next' })

    --[[
        -- Add telescope
        local conf = require('telescope.config').values
        ----
        local function toggle_telescope(harpoon_files)
          ----
          local file_paths = {}
          for _, item in ipairs(harpoon_files.items) do
            table.insert(file_paths, item.value)
          end
          ----
          require('telescope.pickers')
            .new({}, {
              prompt_title = 'Harpoon',
              finder = require('telescope.finders').new_table {
                results = file_paths,
              },
              previewer = conf.file_previewer {},
              sorter = conf.generic_sorter {},
              ----
            })
            :find()
          ----
        end
        vim.keymap.set('n', '<C-e>', function()
          toggle_telescope(harpoon:list())
        end, { desc = 'Open harpoon window' }) --]]
    ----
  end, -- END 'harpoon'.config.function()

  --
}
