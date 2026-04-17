local trade_box = table.deepcopy(data.raw.item["steel-chest"])
local accent_tint = {r = 0.74, g = 0.96, b = 0.58, a = 1}

trade_box.name = "trade-box"
trade_box.localised_name = {"item-name.trade-box"}
trade_box.localised_description = {"item-description.trade-box"}
trade_box.place_result = "trade-box"
trade_box.order = "a[items]-cz[trade-box]"
trade_box.icons = {
  {
    icon = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    tint = accent_tint,
  },
  {
    icon = "__base__/graphics/icons/coin.png",
    icon_size = 64,
    scale = 0.45,
    shift = {10, 10},
  },
}
trade_box.icon = nil

data:extend({trade_box})
