return {
  id = "level_1_habitable_zone",
  title = "Habitable Zone",
  pickerLabel = "WIKI LEVEL 1: Habitable Zone",
  briefing = "The elevator from Level 0 stops early in the Habitable Zone. Wide concrete halls shift between warehouse and parking structure. Find the VHS Tape, Green Valve, and Glass Fuse, then try the UTILITY door. When Flickering starts, reach a bed before the Skin-Stealer gets you.",
  flavorSource = "wiki+openai",
  cellSize = 800,
  origin = {
    x = 120000,
    y = 120000,
    z = 400
  },
  rules = {
    hungerStart = 100,
    staminaStart = 100,
    moveHunger = 15,
    moveStamina = 15,
    refuge = true,
    creeper = "crate",
    exitPipes = true
  },
  coop = {
    sharedVitals = true,
    minPlayers = 1,
    maxPlayers = 6,
    rules = "Three parts lie on small tables in the rooms: a tape, a valve and a fuse. The exit door opens when the group carries all three and somebody tries the door."
  },
  start = "r0_0",
  exit = {
    room = "r3_3",
    requires = {
      "vhs",
      "valve",
      "fuse"
    }
  },
  rooms = {
    {
      id = "r0_0",
      x = 0,
      y = 0,
      theme = "grey_halls",
      description = "You stand in bland grey concrete. A square pillar cuts one corner, and debris lies in small dry piles."
    },
    {
      id = "r1_0",
      x = 1,
      y = 0,
      theme = "grey_halls",
      description = "A Granola Square sits on a small table. Bland walls press close around a square pillar and scattered debris."
    },
    {
      id = "r2_0",
      x = 2,
      y = 0,
      theme = "grey_halls",
      description = "A Quiet Cot rests on the floor. The grey walls are stained, and debris gathers beside one concrete pillar."
    },
    {
      id = "r3_0",
      x = 3,
      y = 0,
      theme = "warehouse_pipes",
      description = "A VHS Tape sits on a small table. Pipes run under the ceiling above a metal shelf stacked with crates."
    },
    {
      id = "r0_1",
      x = 0,
      y = 1,
      theme = "warehouse_pipes",
      description = "A metal shelf of crates leans in one corner. Pipes cross the ceiling and carry a dull clang."
    },
    {
      id = "r1_1",
      x = 1,
      y = 1,
      theme = "stagnant_crates",
      description = "A Buzzing Mattress lies on the floor. Wooden crates sit near a stagnant puddle that smells unclean."
    },
    {
      id = "r2_1",
      x = 2,
      y = 1,
      theme = "warehouse_pipes",
      description = "A Canned Soup sits on a small table. A metal shelf holds crates below two ceiling pipes."
    },
    {
      id = "r3_1",
      x = 3,
      y = 1,
      theme = "gild_sector",
      description = "A Glass Fuse sits on a small table. Warmer concrete surrounds a square pillar and stacked crates."
    },
    {
      id = "r0_2",
      x = 0,
      y = 2,
      theme = "stagnant_crates",
      description = "Wooden crates crowd one corner. A dark puddle spreads a plastic stagnant smell."
    },
    {
      id = "r1_2",
      x = 1,
      y = 2,
      theme = "stagnant_crates",
      description = "Almond Water stands on a small table. Crates sit by a stale puddle on the concrete."
    },
    {
      id = "r2_2",
      x = 2,
      y = 2,
      theme = "gild_sector",
      description = "A Small Key sits on a small table. Varied concrete bands frame a square pillar and a stack of crates."
    },
    {
      id = "r3_2",
      x = 3,
      y = 2,
      theme = "garden_floor",
      description = "Flat green growth crawls over the floor and the foot of the walls. Debris breaks through it in small piles."
    },
    {
      id = "r0_3",
      x = 0,
      y = 3,
      theme = "garden_floor",
      description = "You feel humid air above flat green growth. The floor is broken by wood, packing material, and metal."
    },
    {
      id = "r1_3",
      x = 1,
      y = 3,
      theme = "warehouse_pipes",
      description = "Pipes run over a metal shelf stocked with wooden crates. The air feels stuffy and humid."
    },
    {
      id = "r2_3",
      x = 2,
      y = 3,
      theme = "gild_sector",
      description = "A Green Valve sits on a small table. Color bands cross the concrete beside a square pillar and crates."
    },
    {
      id = "r3_3",
      x = 3,
      y = 3,
      theme = "gild_sector",
      description = "A heavy UTILITY door faces you. Warm concrete, a square pillar, and stacked crates fill the room."
    }
  },
  links = {
    {
      a = "r0_0",
      b = "r1_0",
      lock = nil
    },
    {
      a = "r0_0",
      b = "r0_1",
      lock = nil
    },
    {
      a = "r1_0",
      b = "r2_0",
      lock = nil
    },
    {
      a = "r1_0",
      b = "r1_1",
      lock = nil
    },
    {
      a = "r2_0",
      b = "r3_0",
      lock = nil
    },
    {
      a = "r2_0",
      b = "r2_1",
      lock = nil
    },
    {
      a = "r3_0",
      b = "r3_1",
      lock = nil
    },
    {
      a = "r0_1",
      b = "r1_1",
      lock = nil
    },
    {
      a = "r0_1",
      b = "r0_2",
      lock = nil
    },
    {
      a = "r1_1",
      b = "r2_1",
      lock = nil
    },
    {
      a = "r1_1",
      b = "r1_2",
      lock = nil
    },
    {
      a = "r2_1",
      b = "r3_1",
      lock = nil
    },
    {
      a = "r2_1",
      b = "r2_2",
      lock = nil
    },
    {
      a = "r3_1",
      b = "r3_2",
      lock = nil
    },
    {
      a = "r0_2",
      b = "r1_2",
      lock = nil
    },
    {
      a = "r0_2",
      b = "r0_3",
      lock = nil
    },
    {
      a = "r1_2",
      b = "r2_2",
      lock = nil
    },
    {
      a = "r1_2",
      b = "r1_3",
      lock = nil
    },
    {
      a = "r2_2",
      b = "r3_2",
      lock = nil
    },
    {
      a = "r2_2",
      b = "r2_3",
      lock = nil
    },
    {
      a = "r3_2",
      b = "r3_3",
      lock = "small_key"
    },
    {
      a = "r0_3",
      b = "r1_3",
      lock = nil
    },
    {
      a = "r1_3",
      b = "r2_3",
      lock = nil
    },
    {
      a = "r2_3",
      b = "r3_3",
      lock = "small_key"
    }
  },
  contents = {
    r0_0 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r1_0 = {
      keys = {},
      puzzle = {},
      food = {
        {
          id = "granola",
          name = "Granola Square",
          hunger = 40
        }
      },
      rest = {}
    },
    r2_0 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {
        {
          id = "quiet_cot",
          name = "Quiet Cot",
          stamina = 50,
          callsMonster = false
        }
      }
    },
    r3_0 = {
      keys = {},
      puzzle = {
        {
          id = "vhs",
          name = "VHS Tape",
          clue = "You take the VHS Tape. It joins the door parts."
        }
      },
      food = {},
      rest = {}
    },
    r0_1 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r1_1 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {
        {
          id = "buzzing_mattress",
          name = "Buzzing Mattress",
          stamina = 50,
          callsMonster = true
        }
      }
    },
    r2_1 = {
      keys = {},
      puzzle = {},
      food = {
        {
          id = "canned_soup",
          name = "Canned Soup",
          hunger = 40
        }
      },
      rest = {}
    },
    r3_1 = {
      keys = {},
      puzzle = {
        {
          id = "fuse",
          name = "Glass Fuse",
          clue = "You take the Glass Fuse. It joins the door parts."
        }
      },
      food = {},
      rest = {}
    },
    r0_2 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r1_2 = {
      keys = {},
      puzzle = {},
      food = {
        {
          id = "almond_water",
          name = "Almond Water",
          hunger = 40
        }
      },
      rest = {}
    },
    r2_2 = {
      keys = {
        {
          id = "small_key",
          name = "Small Key"
        }
      },
      puzzle = {},
      food = {},
      rest = {}
    },
    r3_2 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r0_3 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r1_3 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    },
    r2_3 = {
      keys = {},
      puzzle = {
        {
          id = "valve",
          name = "Green Valve",
          clue = "You take the Green Valve. It joins the door parts."
        }
      },
      food = {},
      rest = {}
    },
    r3_3 = {
      keys = {},
      puzzle = {},
      food = {},
      rest = {}
    }
  },
  monsters = {
    {
      id = "entity",
      name = "Skin-Stealer",
      patrol = {
        "r2_0",
        "r3_0",
        "r3_1"
      },
      damage = 20,
      visualClass = "/Game/Entities/SkinStealer/BP_SkinStealer.BP_SkinStealer_C"
    }
  },
  solution = {
    steps = {
      {
        action = "move",
        to = "r1_0"
      },
      {
        action = "move",
        to = "r2_0"
      },
      {
        action = "rest",
        id = "quiet_cot"
      },
      {
        action = "move",
        to = "r3_0"
      },
      {
        action = "take",
        id = "vhs"
      },
      {
        action = "move",
        to = "r3_1"
      },
      {
        action = "take",
        id = "fuse"
      },
      {
        action = "move",
        to = "r2_1"
      },
      {
        action = "eat",
        id = "canned_soup"
      },
      {
        action = "move",
        to = "r2_2"
      },
      {
        action = "take",
        id = "small_key"
      },
      {
        action = "move",
        to = "r2_3"
      },
      {
        action = "take",
        id = "valve"
      },
      {
        action = "move",
        to = "r3_3"
      },
      {
        action = "exit"
      }
    }
  },
  seed = 1360,
  themes = {
    grey_halls = {
      wall = {
        0.31,
        0.31,
        0.3
      },
      band = {
        0.24,
        0.24,
        0.23
      },
      floor = {
        0.29,
        0.29,
        0.28
      },
      ceil = {
        0.27,
        0.27,
        0.26
      },
      trim = {
        0.18,
        0.18,
        0.17
      },
      light = {
        1.0,
        0.92,
        0.82
      },
      power = 0.72,
      props = {
        "pillar",
        "debris"
      }
    },
    warehouse_pipes = {
      wall = {
        0.28,
        0.28,
        0.27
      },
      band = {
        0.2,
        0.2,
        0.2
      },
      floor = {
        0.25,
        0.25,
        0.24
      },
      ceil = {
        0.22,
        0.22,
        0.22
      },
      trim = {
        0.16,
        0.16,
        0.16
      },
      light = {
        0.95,
        0.9,
        0.78
      },
      power = 0.65,
      props = {
        "shelf",
        "pipes"
      }
    },
    stagnant_crates = {
      wall = {
        0.27,
        0.28,
        0.27
      },
      band = {
        0.17,
        0.18,
        0.17
      },
      floor = {
        0.21,
        0.22,
        0.21
      },
      ceil = {
        0.23,
        0.23,
        0.22
      },
      trim = {
        0.14,
        0.14,
        0.13
      },
      light = {
        0.9,
        0.86,
        0.75
      },
      power = 0.58,
      props = {
        "crates",
        "puddle"
      }
    },
    gild_sector = {
      wall = {
        0.36,
        0.33,
        0.27
      },
      band = {
        0.31,
        0.25,
        0.18
      },
      floor = {
        0.3,
        0.29,
        0.26
      },
      ceil = {
        0.28,
        0.27,
        0.24
      },
      trim = {
        0.24,
        0.2,
        0.15
      },
      light = {
        1.0,
        0.94,
        0.78
      },
      power = 0.92,
      props = {
        "pillar",
        "crates"
      }
    },
    garden_floor = {
      wall = {
        0.25,
        0.31,
        0.25
      },
      band = {
        0.16,
        0.27,
        0.16
      },
      floor = {
        0.18,
        0.25,
        0.18
      },
      ceil = {
        0.22,
        0.24,
        0.21
      },
      trim = {
        0.13,
        0.18,
        0.13
      },
      light = {
        0.86,
        0.94,
        0.78
      },
      power = 0.62,
      props = {
        "growth",
        "debris"
      }
    }
  },
  text = {
    intro1 = "The elevator from Level 0 stops early and opens into this place.",
    intro2 = "You see wide bland halls and feel damp air in stained concrete.",
    goal = "Find the VHS Tape, Green Valve, and Glass Fuse. Try the UTILITY door.",
    huntWarn = "When Flickering starts, reach a cot or mattress before it finds you.",
    huntStart = "Flickering takes the room. The Skin-Stealer starts hunting.",
    huntTaken = "The part leaves the table. Flickering starts, and the Skin-Stealer comes.",
    huntEnd = "The Flickering ends. The halls only hum and drip.",
    hudHunt = "FLICKERING",
    refuge = "You crowd by the bed here. The Flickering passes over this room.",
    monsterNear = "{name} watches near you with sunken white eyes.",
    tipDeath = "Flickering wakes hunters. Stay together near a bed.",
    wake = "You wake by the elevator with hunger and stamina half filled.",
    collapse = "Your body gives out.",
    hungry = "Food is scarce. Eat or drink before you fall.",
    tired = "Stuffy air drags at you. Find a bed and rest.",
    eat = "You take in {item}. Down here, resources decide how long you last.",
    keyTaken = "You take the {item}. Locked doors may answer it.",
    restQuiet = "The Quiet Cot takes your weight. The halls stay distant.",
    restLoud = "The Buzzing Mattress groans. Something comes one room closer.",
    doorShut = "The UTILITY door stays shut. Missing: {parts}.",
    doorOpen = "The parts fit. The way to the Utility Halls opens.",
    exitSign = "UTILITY",
    objectiveParts = "Find the tape, valve, and fuse.",
    objectiveKey = "Find the Small Key.",
    objectiveExit = "Enter the UTILITY hall.",
    tipParts = "Parts rest on small tables in rooms.",
    tipHall = "Walk the hall. Do not look back.",
    sealed = "You turn and find only bland wall.",
    chair = "The wooden crate has crept closer while you were not looking.",
    keyTurns = "The Small Key turns without your hand.",
    noDoor = "The dead end remains. The EXIT sign is gone.",
    hallSign = "DO NOT LOOK BACK",
    hallEnter = "Do not look back in this hall.",
    hallLook = "You look back. The hall resets.",
    hallLooked = "You turn back. The distance is gone.",
    hallPace = "A clang follows your pace in the pipes.",
    hallSigns = "The EXIT signs count down overhead. Keep walking. Do not look back.",
    hallLight = "The pipes and dials thin around a far pale opening.",
    epiBig = "A SMALL ROOM",
    epi1 = "The Utility Halls feel close behind a closed sliding door.",
    epi2 = "The plain sign waits to name the common way out.",
    epiSign = "LEVEL 2",
    epiEnd = "AGAIN",
    epi3 = "You step through, and the Habitable Zone begins again.",
    loop = "LOOP {n}. The elevator opens onto the same Habitable Zone.",
    whispers = {
      "You count distance, but the room refuses the number.",
      "A crate waits only while you keep it in sight.",
      "Clangs travel through pipes above your breathing.",
      "The damp air smells of old, stagnant water."
    }
  },
  wiki = {
    site = "https://backrooms-wiki.wikidot.com/",
    level = "level-1",
    entity = "entity-10",
    licence = "CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/)",
    credit = "Lore, names and descriptions are adapted from The Backrooms wiki (https://backrooms-wiki.wikidot.com/), pages: https://backrooms-wiki.wikidot.com/level-1, https://backrooms-wiki.wikidot.com/entity-10, https://backrooms-wiki.wikidot.com/object-1. Licensed CC BY-SA 3.0.",
    difficulty = {
      class = "1",
      lines = {
        "Safe and Secure.",
        "Presence of Anomalous Resources."
      }
    },
    exitTo = "Level 2"
  }
}
