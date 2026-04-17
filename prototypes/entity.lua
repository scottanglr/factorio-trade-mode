local trade_box = table.deepcopy(data.raw.container["steel-chest"])

trade_box.name = "trade-box"
trade_box.minable = {mining_time = 0.2, result = "trade-box"}
trade_box.localised_name = {"entity-name.trade-box"}
trade_box.localised_description = {"entity-description.trade-box"}
trade_box.inventory_type = "with_filters_and_bar"
trade_box.icons = {
  {
    icon = "__base__/graphics/icons/steel-chest.png",
    tint = {r = 0.85, g = 1, b = 0.6, a = 1},
  },
}
trade_box.icon = nil
trade_box.picture.layers[1].tint = {r = 0.85, g = 1, b = 0.6, a = 1}

data:extend({trade_box})

