data:extend({
  {
    type = "shortcut",
    name = "trade-mode-open-panel",
    order = "g[trade-mode]",
    localised_name = {"shortcut-name.trade-mode-open-panel"},
    localised_description = {"shortcut-description.trade-mode-open-panel"},
    associated_control_input = "trade-mode-toggle-market",
    action = "lua",
    toggleable = true,
    style = "green",
    icons = {
      {
        icon = "__base__/graphics/icons/steel-chest.png",
        icon_size = 64,
        tint = {r = 0.74, g = 0.96, b = 0.58, a = 1},
      },
      {
        icon = "__base__/graphics/icons/coin.png",
        icon_size = 64,
        scale = 0.45,
        shift = {10, 10},
      },
    },
    small_icons = {
      {
        icon = "__base__/graphics/icons/steel-chest.png",
        icon_size = 64,
        tint = {r = 0.74, g = 0.96, b = 0.58, a = 1},
      },
      {
        icon = "__base__/graphics/icons/coin.png",
        icon_size = 64,
        scale = 0.45,
        shift = {10, 10},
      },
    },
  },
})
