local trade_box = table.deepcopy(data.raw.item["steel-chest"])

trade_box.name = "trade-box"
trade_box.localised_name = {"item-name.trade-box"}
trade_box.localised_description = {"item-description.trade-box"}
trade_box.place_result = "trade-box"
trade_box.order = "a[items]-cz[trade-box]"
trade_box.icons = {
  {
    icon = "__base__/graphics/icons/steel-chest.png",
    tint = {r = 0.85, g = 1, b = 0.6, a = 1},
  },
}
trade_box.icon = nil

data:extend({trade_box})

