local agricultural_roboport_settings = {
  {
    type = "bool-setting",
    name = "agricultural-roboport-dense-seeding",
    setting_type = "startup",
    default_value = false,
    order = "a-1"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-max-seeds-per-tick",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a"
  },
  {
    type = "bool-setting",
    name = "agricultural-roboport-ignore-cliffs",
    setting_type = "runtime-global",
    default_value = false,
    order = "b"
  }
  ,
  {
    type = "bool-setting",
    name = "agricultural-roboport-debug",
    setting_type = "runtime-global",
    default_value = false,
    order = "b-1"
  }
  ,
  {
    type = "bool-setting",
    name = "agricultural-roboport-mutation-visualization",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "b-2"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-tdm-period",
    setting_type = "runtime-global",
    default_value = 300,
    minimum_value = 30,
    maximum_value = 3600,
    order = "c"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-tdm-tick-interval",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 300,
    order = "d"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-seed-checks-per-call",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 1000,
    order = "e"
  },
  {
    type = "int-setting",
    name = "agricultural-roboport-max-harvest-per-call",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 100,
    order = "f"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-harvest-checks-per-call",
    setting_type = "runtime-global",
    default_value = 8,
    minimum_value = 1,
    maximum_value = 1000,
    order = "g"
  }
  ,
  {
    type = "int-setting",
    name = "agricultural-roboport-quality-improvement-chance",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 100,
    order = "h-1",
    hidden = true  -- Replaced by controlled mutations research
  }}
  if mods["quality"] then 
	log("Quality mod detected: Enabling quality settings for Agricultural Roboport");
	table.insert(agricultural_roboport_settings,  
	{
    type = "bool-setting",
    name = "agricultural-roboport-enable-quality",
    setting_type = "startup",
    default_value = true,
    order = "a-0"
  })
else 
	log("Quality mod not detected: Skipping quality settings for Agricultural Roboport");
	table.insert(agricultural_roboport_settings,  
	{
	type = "bool-setting",
	name = "agricultural-roboport-enable-quality",
	setting_type = "startup",
	default_value = false,
	hidden = true,
	order = "a-0"
  })
end
data:extend(agricultural_roboport_settings)
