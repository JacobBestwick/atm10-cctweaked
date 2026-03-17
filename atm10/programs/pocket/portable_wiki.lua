-- portable_wiki.lua
-- ATM10 Portable Quick-Reference Wiki
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: None (fully offline)
--
-- A pocket-sized ATM10 knowledge base covering all major mods.
-- Browse mod sections, recipes, tips, and your own notes.
-- Everything works offline — no modem needed.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "portable_wiki.cfg"
local DEFAULTS = {
  userNotes = {},
  bookmarks  = {},
}

-- ─────────────────────────────────────────────
-- Wiki content
-- Each section is a table of page tables:
--   { title=string, lines={string,...} }
-- ─────────────────────────────────────────────
local WIKI = {}

-- ──────────────────────────────────────────────
-- MEKANISM
-- ──────────────────────────────────────────────
WIKI["Mekanism"] = {
  {
    title = "Mekanism Overview",
    lines = {
      "MEKANISM",
      "========================",
      "",
      "Mekanism is the core tech mod of",
      "ATM10. It adds 5x ore processing,",
      "advanced power generation, gas",
      "handling, and late-game machines.",
      "",
      "POWER UNITS: Joules (J)",
      "  1 FE  = 2.5 J",
      "  1 J   = 0.4 FE",
      "",
      "PROGRESSION:",
      "  1. Basic machines (Enrichment",
      "     Chamber, Crusher, Combiner)",
      "  2. Steel production",
      "  3. 3x ore processing",
      "  4. Infuser + Metallurgic Infuser",
      "  5. 5x ore processing chain",
      "  6. Fusion Reactor / Fission",
      "",
      "KEY RESOURCES:",
      "  - Osmium Ore (found Y:-30 to 30)",
      "  - Tin, Lead, Uranium ores",
      "  - Steel (iron + carbon in infuser)",
      "",
    },
  },
  {
    title = "5x Ore Processing",
    lines = {
      "MEKANISM 5X ORE PROCESSING",
      "===========================",
      "",
      "Tier 1 (2x): Enrichment Chamber",
      "  Ore → 2x Dust → Smelter → Ingot",
      "",
      "Tier 2 (3x): Chemical Injection",
      "  Ore + Hydrogen Chloride",
      "  → 3x Shards → Purification → Dust",
      "",
      "Tier 3 (4x): Purification Chamber",
      "  Ore + Oxygen → 4x Clumps",
      "  → Crusher → Dust → Enrichment",
      "",
      "Tier 4 (5x): Chemical Dissolution",
      "  Ore + Sulfuric Acid",
      "  → Slurry → Washing (water)",
      "  → Clean Slurry → Crystallize",
      "  → Crystal → Inject → Shard",
      "  → Purify → Clump → Crush → Dust",
      "  → Enrich → 5x Ingot",
      "",
      "GAS SOURCES:",
      "  Oxygen:  Electrolytic Separator",
      "           (water → H2 + O2)",
      "  HCl:     Chemical Infuser",
      "           (H2 + Cl from brine)",
      "  H2SO4:   Brine → Electrolysis",
      "           → Cl + Sulfur Dioxide",
      "",
    },
  },
  {
    title = "Mekanism Power",
    lines = {
      "MEKANISM POWER GENERATION",
      "==========================",
      "",
      "EARLY: Solar Generator",
      "  ~120 J/t day, 0 at night",
      "  Advanced Solar: ~480 J/t",
      "",
      "EARLY: Wind Generator",
      "  Higher altitude = more power",
      "  Max ~480 J/t at Y=255",
      "  Place above Y 200 for best",
      "",
      "MID: Bio-Generator",
      "  Converts biomass to power",
      "  ~450 J/t",
      "",
      "MID: Gas Burning Generator",
      "  Burns Hydrogen or Ethylene",
      "  Hydrogen:  ~1500 J/t",
      "  Ethylene:  ~7680 J/t",
      "  Tip: Run Electrolytic Separator",
      "       → store H2 → burn for power",
      "",
      "LATE: Fusion Reactor",
      "  Requires: Deuterium + Tritium",
      "  Ignition: 400 MJ laser",
      "  Output: up to 400 MJ/t",
      "  Self-sustaining once started!",
      "",
      "LATE: Fission Reactor",
      "  Burns Nuclear Waste",
      "  Power: configurable burn rate",
      "  WARNING: Meltdown possible!",
      "  Always use pressure relief valve",
      "",
    },
  },
  {
    title = "Key Mekanism Recipes",
    lines = {
      "MEKANISM KEY RECIPES",
      "=====================",
      "",
      "STEEL INGOT:",
      "  Metallurgic Infuser:",
      "  Iron Ingot + 10 Carbon",
      "  (Carbon from Coal/Charcoal/",
      "   Graphite Dust in Enricher)",
      "",
      "STEEL CASING:",
      "  4x Steel Ingot + 4x Osmium",
      "  + 1 Glass (center)",
      "  Crafting table",
      "",
      "BASIC CONTROL CIRCUIT:",
      "  Osmium Ingot + Redstone",
      "  Metallurgic Infuser (Redstone)",
      "",
      "ADVANCED CONTROL CIRCUIT:",
      "  Basic Circuit + Gold (infuser)",
      "",
      "ELITE CONTROL CIRCUIT:",
      "  Advanced Circuit + Diamond",
      "",
      "ULTIMATE CONTROL CIRCUIT:",
      "  Elite + Netherite Ingot",
      "",
      "ALLOY (Basic/Advanced/Elite):",
      "  Enriched Iron/Steel/Diamond",
      "  in Metallurgic Infuser",
      "",
      "HDPE PELLET:",
      "  Ethylene → Thermal Evaporation",
      "  → Polyethylene process",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- AE2 (Applied Energistics 2)
-- ──────────────────────────────────────────────
WIKI["AE2"] = {
  {
    title = "AE2 Overview",
    lines = {
      "APPLIED ENERGISTICS 2",
      "======================",
      "",
      "AE2 is the primary storage system",
      "in ATM10. Everything is stored as",
      "digital bytes on drives.",
      "",
      "POWER: AE uses EU internally",
      "  Accepts FE via Energy Acceptor",
      "",
      "CORE COMPONENTS:",
      "  ME Controller  - network heart",
      "  ME Drive       - holds drives",
      "  ME Terminal    - access storage",
      "  Storage Bus    - connects chests",
      "  Import/Export  - I/O buses",
      "",
      "PROGRESSION:",
      "  1. Certus Quartz (mine or grow)",
      "  2. Fluix Crystal (charged quartz",
      "     + nether quartz + redstone",
      "     thrown in water)",
      "  3. Printed circuits (inscriber)",
      "  4. ME Drive + 1k drive",
      "  5. Autocrafting CPUs",
      "  6. Spatial Storage / P2P",
      "",
    },
  },
  {
    title = "AE2 Crystals & Seeds",
    lines = {
      "AE2 CRYSTALS",
      "=============",
      "",
      "CERTUS QUARTZ:",
      "  - Mines underground (Y: -30-50)",
      "  - OR grow Crystal Seeds in water",
      "    (slow, ~20 min per crystal)",
      "  - Used for almost everything",
      "",
      "CHARGED CERTUS QUARTZ:",
      "  - Throw Certus into water with",
      "    a Charged Certus Quartz throw",
      "  - OR use Charger block",
      "    (needs Vibration Chamber power)",
      "",
      "FLUIX CRYSTAL:",
      "  - Throw in water:",
      "    1x Charged Certus",
      "    + 1x Nether Quartz",
      "    + 1x Redstone",
      "  - Wait ~30s for reaction",
      "",
      "PURE CRYSTALS (Fluix, Certus):",
      "  - Grow Seeds in fully illuminated",
      "    water (light level 15)",
      "  - Faster than impure versions",
      "",
      "TIPS:",
      "  - Annihilation Plane auto-harvests",
      "  - Crystal Growth Accelerator 4x",
      "",
    },
  },
  {
    title = "AE2 Storage",
    lines = {
      "AE2 STORAGE SYSTEM",
      "===================",
      "",
      "STORAGE CELLS (item types/bytes):",
      "  1k   = 8 types,   1024 bytes",
      "  4k   = 32 types,  4096 bytes",
      "  16k  = 128 types, 16384 bytes",
      "  64k  = 256 types, 65536 bytes",
      "  256k = 256 types, 262144 bytes",
      "",
      "BYTES USED:",
      "  1 item type  = 1 byte baseline",
      "  + 1 byte per 8 additional items",
      "  (store fewer types = more items)",
      "",
      "PARTITIONING CELLS:",
      "  Use Cell Workbench to restrict",
      "  a cell to specific items.",
      "  Partitioned cells are 8x efficient",
      "  for those items!",
      "",
      "STORAGE PRIORITY:",
      "  Higher priority drives fill first.",
      "  Set on Storage Bus / Drive.",
      "  Use to prefer specific cells.",
      "",
      "DRIVES vs CHEST-STORAGE:",
      "  ME Drive holds up to 10 cells",
      "  Storage Bus imports existing",
      "    chests into the network",
      "",
    },
  },
  {
    title = "AE2 Autocrafting",
    lines = {
      "AE2 AUTOCRAFTING",
      "=================",
      "",
      "REQUIREMENTS:",
      "  ME Crafting Storage (1k-64k)",
      "  ME Crafting Monitor (optional)",
      "  ME Crafting CPU (1+ per job)",
      "  Patterns in Interfaces",
      "",
      "PATTERN TYPES:",
      "  Crafting Pattern - 3x3 recipe",
      "  Processing Pattern - A→B via",
      "    machine (e.g. furnace, press)",
      "",
      "SETUP:",
      "  1. Inscribe pattern in Encoder",
      "     (Blank Pattern + recipe)",
      "  2. Place Pattern in ME Interface",
      "  3. Connect Interface to machine",
      "  4. Request item in terminal!",
      "",
      "MOLECULAR ASSEMBLER:",
      "  Auto-crafter for AE2",
      "  Attach to ME Interface",
      "  Can handle crafting patterns",
      "  Only needs interfaces touching",
      "",
      "CRAFTING CPUs:",
      "  1 CPU unit = 1 parallel job",
      "  Co-Processor = +1 parallel op",
      "  Bigger CPUs for complex recipes",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- BOTANIA
-- ──────────────────────────────────────────────
WIKI["Botania"] = {
  {
    title = "Botania Overview",
    lines = {
      "BOTANIA",
      "========",
      "",
      "Botania is a magic-tech mod using",
      "flowers to generate Mana (magical",
      "energy stored in Mana Pools).",
      "",
      "BOOK: Read the Lexica Botania!",
      "  Craft: Book + Sapling",
      "  Contains ALL recipes in-game.",
      "",
      "MANA FLOW:",
      "  Flowers → Mana Spreader",
      "  → Mana Pool → Mana Tablet",
      "  → Mana Enchanter / Tools",
      "",
      "MANA UNITS:",
      "  Full Mana Pool = 1,000,000 mana",
      "  Diluted Pool   = 10,000 mana",
      "",
      "KEY PROGRESSION:",
      "  1. Pure Daisy (stone → livingrock)",
      "  2. Endoflame (burns items for mana)",
      "  3. Mana Pool + Spreader",
      "  4. Runic Altar for runes",
      "  5. Terrasteel",
      "  6. Elementium & Pixies",
      "  7. Gaia Guardian (boss)",
      "  8. Alfheim portal",
      "",
    },
  },
  {
    title = "Botania Key Recipes",
    lines = {
      "BOTANIA KEY RECIPES",
      "====================",
      "",
      "LIVINGROCK:",
      "  Stone → place near Pure Daisy",
      "  Wait ~1 minute to convert",
      "",
      "LIVINGWOOD:",
      "  Oak Log → place near Pure Daisy",
      "",
      "MANASTEEL INGOT:",
      "  3x Iron Ingot + 1 Mana Pearl",
      "  + 1 Mana Powder",
      "  Infused in Mana Pool (uses mana)",
      "",
      "TERRASTEEL INGOT:",
      "  1 Manasteel + 1 Mana Diamond",
      "  + 1 Mana Pearl",
      "  On Terrestrial Agglomeration Plate",
      "  Requires: 3 full Mana Pools nearby",
      "  WARNING: Destroys pools' mana!",
      "",
      "ELEMENTIUM INGOT:",
      "  2 Manasteel ingots",
      "  In Elven Trade portal",
      "  (Give to elves, get back 2x)",
      "",
      "GAIA SPIRIT:",
      "  Drop from Gaia Guardian boss",
      "  Summon with Gaia Pylons at night",
      "  + Terrasteel on Beacon",
      "",
      "MANA TABLET:",
      "  Livingwood Twig (crafted)",
      "  + Manasteel + Mana Pearl",
      "",
    },
  },
  {
    title = "Botania Flowers",
    lines = {
      "BOTANIA GENERATING FLOWERS",
      "===========================",
      "(Produces mana)",
      "",
      "ENDOFLAME:",
      "  Burns any burnable item",
      "  ~6.5 mana/tick while burning",
      "  Use Hopper to feed coal",
      "",
      "HYDROANGEAS:",
      "  Generates near water",
      "  Very slow, good for AFK setups",
      "",
      "ENTROPINNYUM:",
      "  Eats TNT explosions",
      "  Huge mana per TNT",
      "  Requires dispensers + timing",
      "",
      "KEKIMURUS:",
      "  Eats cake blocks",
      "  Good mana rate, renewable",
      "",
      "GOURMARYLLIS:",
      "  Eats food items",
      "  More mana for diverse foods",
      "  Alternating food = more mana",
      "",
      "ROSA ARCANA:",
      "  Consumes XP orbs",
      "  Great with XP farms",
      "",
      "DANDELIFEON:",
      "  Game of Life automaton",
      "  Complex setup, huge output",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- CREATE
-- ──────────────────────────────────────────────
WIKI["Create"] = {
  {
    title = "Create Overview",
    lines = {
      "CREATE MOD",
      "===========",
      "",
      "Create adds kinetic (rotational)",
      "machinery. All machines need",
      "Stress Units (SU) of rotation.",
      "",
      "POWER SOURCES:",
      "  Windmill Bearing + Sails",
      "    (up to 2048 SU, needs wind)",
      "  Water Wheel (128-192 SU)",
      "  Mechanical Bearing + Flywheel",
      "  Steam Engine (late game)",
      "",
      "STRESS UNITS:",
      "  Every machine has SU capacity",
      "  If total SU > source capacity",
      "  → network stops! Add more power",
      "",
      "ROTATION SPEED:",
      "  Higher RPM = faster machines",
      "  Use Gearbox to transfer rotation",
      "  Cogwheels: change speed/direction",
      "  Large Cogwheel → Small = 2x speed",
      "  Shaft to transfer over distance",
      "",
      "KEY MACHINES:",
      "  Mechanical Press - crafting",
      "  Mechanical Mixer - crafting",
      "  Millstone - grinding",
      "  Encased Fan - smelting/washing",
      "  Deployer - auto-place items",
      "  Mechanical Drill - mining",
      "",
    },
  },
  {
    title = "Create Contraptions",
    lines = {
      "CREATE CONTRAPTIONS",
      "====================",
      "",
      "MOVING STRUCTURES:",
      "  Mechanical Bearing + blocks",
      "  Rope Pulley / Linear Chassis",
      "  Windmill blades (Sails)",
      "",
      "ITEM TRANSPORT:",
      "  Chute - vertical item flow",
      "  Depot - holds items for tools",
      "  Belt - horizontal transport",
      "  Funnel - input/output to belt",
      "  Brass Tunnel - splitting/merging",
      "",
      "CRAFTING MACHINES:",
      "  Mechanical Press:",
      "    Needs Pressing (iron → sheet)",
      "    Packing/Unpacking",
      "  Mechanical Mixer:",
      "    Needs Basin below",
      "    Crafts shapeless recipes",
      "  Mechanical Saw:",
      "    Cuts logs → planks",
      "    Also cuts stone",
      "",
      "SCHEMATIC & QUILL:",
      "  Capture any structure",
      "  Schematicannon to build it!",
      "  Uses Schematic blocks",
      "",
      "TIPS:",
      "  Goggles show SU usage",
      "  Wrench to rotate/move machines",
      "  Shift+scroll to adjust settings",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- POWAH
-- ──────────────────────────────────────────────
WIKI["Powah"] = {
  {
    title = "Powah Overview",
    lines = {
      "POWAH",
      "======",
      "",
      "Powah adds powerful RF/FE energy",
      "generation and storage for ATM10.",
      "",
      "GENERATORS (FE/t output):",
      "  Furnator (Starter):   ~40 FE/t",
      "  Furnator (Basic):    ~120 FE/t",
      "  Thermoelectric Gen:  varies",
      "  Magmator:            ~400 FE/t",
      "  Solar Panel Starter: ~4 FE/t",
      "  Solar Basic-Niotic: escalating",
      "  Reactor (Starter):  ~400 FE/t",
      "  Reactor (Niotic): ~40,000 FE/t",
      "",
      "STORAGE:",
      "  Energy Cell - compact FE storage",
      "  Ender Cell - wireless transfer",
      "",
      "REACTOR FUELS:",
      "  Dry Ice + Water = Snowflake",
      "  Uraninite = Uranium fuel",
      "  Spirited Blossom (from Quartz)",
      "  Blazing Crystal (from Blaze)",
      "",
      "PROGRESSION:",
      "  1. Furnator (burn coal/charcoal)",
      "  2. Magmator (lava input)",
      "  3. Reactor Starter",
      "  4. Reactor Basic → Advanced",
      "     → Blazing → Niotic → Spirited",
      "",
    },
  },
  {
    title = "Powah Reactor Setup",
    lines = {
      "POWAH REACTOR SETUP",
      "====================",
      "",
      "COMPONENTS (per reactor):",
      "  1x Reactor Core",
      "  2x Reactor Controller",
      "  8x Reactor Casing (minimum)",
      "  1x Reactor Cell (at least 1)",
      "  Fuel Rod rods (in cell)",
      "  Moderator blocks (optional)",
      "",
      "BUILD:",
      "  3x3x3 hollow cube minimum",
      "  Core in center",
      "  Casing fills walls",
      "  Cell holds fuel",
      "",
      "FUELS (lowest → highest output):",
      "  Starter: Dry Ice + Uraninite",
      "  Basic:   + Blazing Crystal",
      "  Advanced:+ Niotic Crystal",
      "  Blazing: Blazing fuel rods",
      "  Niotic:  Niotic fuel rods",
      "  Spirited:Spirited fuel rods",
      "  Nitro:   Nitro fuel rods",
      "",
      "MODERATORS boost efficiency:",
      "  Iron Block: small boost",
      "  Gold Block: medium boost",
      "  Diamond Block: large boost",
      "  Emerald Block: larger boost",
      "  Carbon (Graphite): very large",
      "",
      "HEAT MANAGEMENT:",
      "  Add heat sink cells",
      "  Or cooling/moderator blocks",
      "  Reactor can overheat → explode!",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- ORE PROCESSING
-- ──────────────────────────────────────────────
WIKI["Ore Processing"] = {
  {
    title = "Ore Y-Level Guide",
    lines = {
      "ORE Y-LEVEL GUIDE (ATM10)",
      "==========================",
      "",
      "Note: ATM10 uses 1.18+ generation",
      "(Y -64 to 320 world height)",
      "",
      "IRON: Y 15 to -63 (peaks at -16)",
      "COPPER: Y 48 (above sea level)",
      "GOLD: Y -16 to -63 (peaks -16)",
      "COAL: Y 0 to 256 (peaks Y 96)",
      "LAPIS: Y 0 (equal above/below)",
      "REDSTONE: Y -63 to -32",
      "DIAMOND: Y -63 to -16",
      "EMERALD: Mountains Y 256-100",
      "ANCIENT DEBRIS: Y 8-22",
      "QUARTZ: Nether Y 10-117",
      "",
      "MODDED ORES:",
      "OSMIUM (Mekanism): Y -30 to 30",
      "TIN: Y -30 to 60",
      "LEAD: Y -60 to 10",
      "URANIUM: Y -50 to 0",
      "CERTUS QUARTZ: Y -30 to 50",
      "FLUORITE: Y -60 to 0",
      "ALLTHEMODIUM: Deep Dark Y -60",
      "VIBRANIUM: End (any Y)",
      "UNOBTAINIUM: Nether deepslate",
      "",
    },
  },
  {
    title = "ATM Materials",
    lines = {
      "ATM STAR MATERIALS",
      "===================",
      "",
      "ALLTHEMODIUM INGOT:",
      "  Found in Deep Dark (-60 to -64)",
      "  Very rare, fortune helps slightly",
      "  Used in ATM Star components",
      "",
      "VIBRANIUM INGOT:",
      "  Found in The End",
      "  Any Y level in End islands",
      "  Medium rarity",
      "",
      "UNOBTAINIUM INGOT:",
      "  Found in Nether deepslate",
      "  (The Nether equivalent ~Y -50+)",
      "  Rarest of the three",
      "",
      "ATM ALLOYS (crafted):",
      "  Allthemodium Alloy:",
      "    Allthemodium + Netherite",
      "  Vibranium Alloy:",
      "    Vibranium + Allthemodium",
      "  Unobtainium Alloy:",
      "    Unobtainium + Vibranium",
      "",
      "ATM STAR RECIPE:",
      "  Check JEI/REI in-game!",
      "  Requires: All alloys + many",
      "  end-game materials from all mods",
      "  Craft on Crafting Altar",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- TIPS & TRICKS
-- ──────────────────────────────────────────────
WIKI["Tips & Tricks"] = {
  {
    title = "General ATM10 Tips",
    lines = {
      "ATM10 GENERAL TIPS",
      "===================",
      "",
      "EARLY GAME:",
      "  - Install Cyclic or Quark early",
      "    for backpack + inventory",
      "  - Farmer's Delight crops early",
      "    for food diversity",
      "  - Get a Waystones network set up",
      "  - Magnet mod (Pipez/similar) for",
      "    auto item pickup is crucial",
      "",
      "POWER MANAGEMENT:",
      "  - Always overbuild power!",
      "    AE2 + Mekanism eats FE fast",
      "  - Build Powah reactors ASAP",
      "  - Use Energy Cells as buffers",
      "",
      "STORAGE:",
      "  - AE2 early, RS is simpler",
      "  - Partition cells for efficiency",
      "  - Storage Drawers for bulk items",
      "  - Keep 64k+ cells for late game",
      "",
      "MOB FARMS:",
      "  - Wither Skeleton farm for coal",
      "  - Blaze farm for Powah rods",
      "  - Enderman farm for Ender Pearls",
      "  - Dark room spawner is fastest",
      "",
      "TIPS:",
      "  - /ftbquests for quest guide",
      "  - JEI F key on item = recipe",
      "  - Shift+JEI on item = uses",
      "  - Jade mod shows block info (Z)",
      "",
    },
  },
  {
    title = "CC:Tweaked Tips",
    lines = {
      "CC:TWEAKED TIPS (ATM10)",
      "========================",
      "",
      "GETTING STARTED:",
      "  - Craft Pocket Computer first",
      "  - Attach wireless modem for net",
      "  - Advanced Pocket = colors!",
      "",
      "THIS SUITE PROGRAMS:",
      "  Hub      - main launcher",
      "  remote_dash - base overview",
      "  gps_nav  - GPS navigation",
      "  remote_craft - craft remotely",
      "  ender_link - ender frequencies",
      "  portable_wiki - this guide!",
      "  player_scanner - find players",
      "",
      "BASE PROGRAMS:",
      "  base_monitor - live dashboard",
      "  craft_manager - autocrafting",
      "  power_grid - power monitor",
      "  resource_tracker - goals",
      "  farm_controller - farm auto",
      "  security_system - intruder alert",
      "",
      "TURTLE PROGRAMS:",
      "  smart_miner - branch mining",
      "  quarry_turtle - area quarry",
      "  tunnel_bore - long tunnels",
      "  tree_farmer - auto tree farm",
      "",
      "FILES STORED IN:",
      "  /atm10/data/  - config + logs",
      "  /atm10/lib/   - shared libs",
      "",
    },
  },
}

-- ──────────────────────────────────────────────
-- Navigation helpers
-- ──────────────────────────────────────────────
local SECTION_NAMES = {
  "Mekanism",
  "AE2",
  "Botania",
  "Create",
  "Powah",
  "Ore Processing",
  "Tips & Tricks",
}

local function showPage(page, sectionName)
  local lines = {}
  for _, l in ipairs(page.lines) do
    table.insert(lines, l)
  end
  ui.pager(lines, sectionName .. ": " .. page.title)
end

local function browseSection(sectionName)
  local pages = WIKI[sectionName]
  if not pages then return end

  while true do
    local items = {}
    for _, page in ipairs(pages) do
      table.insert(items, { label = page.title })
    end
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, sectionName)
    if not idx or idx > #pages then return end

    showPage(pages[idx], sectionName)
  end
end

-- ─────────────────────────────────────────────
-- User notes
-- ─────────────────────────────────────────────
local function manageNotes(cfg)
  while true do
    local items = {}
    for i, note in ipairs(cfg.userNotes) do
      local preview = (note.title or "Note " .. i):sub(1, 22)
      table.insert(items, { label = preview })
    end
    table.insert(items, { label = "+ New Note" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "My Notes")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      -- New note
      local title = ui.inputText("Note title: ")
      if not title or title == "" then return end
      local body = ui.inputText("Content: ")
      table.insert(cfg.userNotes, { title = title, body = body or "" })
      config.save(CFG_FILE, cfg)
      ui.alert("Note saved!", "success")
    else
      -- View/edit note
      local note = cfg.userNotes[idx]
      local opts = {
        { label = "View" },
        { label = "Delete" },
        { label = "< Cancel" },
      }
      local oidx = ui.drawMenu(opts, note.title or "Note")
      if oidx == 1 then
        ui.pager({ note.title or "", string.rep("-", 26), "", note.body or "" }, "Note")
      elseif oidx == 2 then
        if ui.confirm("Delete note '" .. (note.title or "?") .. "'?") then
          table.remove(cfg.userNotes, idx)
          config.save(CFG_FILE, cfg)
          ui.alert("Deleted.", "success")
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Search
-- ─────────────────────────────────────────────
local function searchWiki()
  local query = ui.inputText("Search wiki: ")
  if not query or query == "" then return end
  query = query:lower()

  local results = {}
  for _, secName in ipairs(SECTION_NAMES) do
    local pages = WIKI[secName]
    if pages then
      for _, page in ipairs(pages) do
        local found = page.title:lower():find(query, 1, true)
        if not found then
          for _, line in ipairs(page.lines) do
            if line:lower():find(query, 1, true) then
              found = true; break
            end
          end
        end
        if found then
          table.insert(results, { section = secName, page = page })
        end
      end
    end
  end

  if #results == 0 then
    ui.alert("No results for '" .. query .. "'", "info")
    return
  end

  local items = {}
  for _, r in ipairs(results) do
    table.insert(items, {
      label       = r.page.title:sub(1, 20),
      description = r.section:sub(1, 8),
    })
  end
  table.insert(items, { label = "< Back" })

  local idx = ui.drawMenu(items, "Results: " .. query)
  if not idx or idx > #results then return end

  local r = results[idx]
  showPage(r.page, r.section)
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local running = true
  while running do
    local items = {}
    for _, name in ipairs(SECTION_NAMES) do
      local pages = WIKI[name]
      table.insert(items, {
        label       = name,
        description = pages and (#pages .. " pages") or "0 pages",
      })
    end
    table.insert(items, { label = "My Notes",    description = #cfg.userNotes .. " notes" })
    table.insert(items, { label = "Search",       description = "find by keyword" })
    table.insert(items, { label = "< Back to Hub", description = "" })

    local idx = ui.drawMenu(items, "Portable Wiki")
    local total = #SECTION_NAMES + 3  -- sections + notes + search + back

    if not idx or idx == total then
      running = false; break
    end

    if idx <= #SECTION_NAMES then
      browseSection(SECTION_NAMES[idx])
    elseif idx == #SECTION_NAMES + 1 then
      manageNotes(cfg)
    elseif idx == #SECTION_NAMES + 2 then
      searchWiki()
    end
  end
end

main()
