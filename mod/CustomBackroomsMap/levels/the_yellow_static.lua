return {
  id = "the_yellow_static",
  title = "Flickering Halls",
  pickerLabel = "AI: Flickering Halls",
  briefing = "You find yourselves trapped in a labyrinth of yellow rooms, each with damp carpet underfoot and humming fluorescent lights overhead. The air is thick with a musty scent, and the distant buzz of electricity is ever-present. Strange objects lie scattered, hinting at forgotten stories and hidden secrets. Stay alert and work together to uncover the way out before the lights dim forever.",
  flavorSource = "openai",
  cellSize = 800,
  origin = {
    x = 120000,
    y = 120000,
    z = 400
  },
  rules = {},
  coop = {
    minPlayers = 1,
    maxPlayers = 6,
    rules = "Anyone can carry a part. The exit opens only when the group has the tape, the valve, and the fuse."
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
      theme = "yellow_wallpaper",
      description = "Yellow paper sags off the wall. The hum in the lamps has nowhere to go."
    },
    {
      id = "r1_0",
      x = 1,
      y = 0,
      theme = "damp_office",
      description = "A lone granola square rests on the damp carpet, untouched and slightly stale."
    },
    {
      id = "r2_0",
      x = 2,
      y = 0,
      theme = "pool_tile",
      description = "A quiet cot sits silently against the wall, its fabric worn and faded."
    },
    {
      id = "r3_0",
      x = 3,
      y = 0,
      theme = "concrete_hall",
      description = "An unlabeled tape lies coiled on the floor, its contents a mystery."
    },
    {
      id = "r0_1",
      x = 0,
      y = 1,
      theme = "damp_office",
      description = "A damp cubicle row. The chairs are warm, as if someone stood up a moment ago."
    },
    {
      id = "r1_1",
      x = 1,
      y = 1,
      theme = "pool_tile",
      description = "A buzzing mattress vibrates faintly, emitting a low, unsettling hum."
    },
    {
      id = "r2_1",
      x = 2,
      y = 1,
      theme = "concrete_hall",
      description = "A can of soup sits unopened, its label faded but still legible. Left here: Canned soup."
    },
    {
      id = "r3_1",
      x = 3,
      y = 1,
      theme = "drop_ceiling",
      description = "A glass fuse glints under the flickering lights, fragile and delicate."
    },
    {
      id = "r0_2",
      x = 0,
      y = 2,
      theme = "pool_tile",
      description = "White tile and standing water. The far splash never shows a swimmer."
    },
    {
      id = "r1_2",
      x = 1,
      y = 2,
      theme = "concrete_hall",
      description = "A bottle of almond water stands chilled, condensation dripping down its sides."
    },
    {
      id = "r2_2",
      x = 2,
      y = 2,
      theme = "drop_ceiling",
      description = "A small brass key gleams faintly, hinting at locked secrets nearby."
    },
    {
      id = "r3_2",
      x = 3,
      y = 2,
      theme = "yellow_wallpaper",
      description = "Yellow paper sags off the wall. The hum in the lamps has nowhere to go."
    },
    {
      id = "r0_3",
      x = 0,
      y = 3,
      theme = "concrete_hall",
      description = "Bare concrete and a red exit sign that points back into the rooms."
    },
    {
      id = "r1_3",
      x = 1,
      y = 3,
      theme = "drop_ceiling",
      description = "A drop ceiling with one dark panel. Dust falls when the group walks in step."
    },
    {
      id = "r2_3",
      x = 2,
      y = 3,
      theme = "yellow_wallpaper",
      description = "A green valve protrudes from the wall, its purpose unclear but inviting interaction."
    },
    {
      id = "r3_3",
      x = 3,
      y = 3,
      theme = "damp_office",
      description = "A damp cubicle row. The chairs are warm, as if someone stood up a moment ago."
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
          name = "Granola square"
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
          name = "Quiet cot"
        }
      }
    },
    r3_0 = {
      keys = {},
      puzzle = {
        {
          id = "vhs",
          name = "Unlabeled tape",
          clue = "The sleeve says the door drinks light."
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
          name = "Buzzing mattress"
        }
      }
    },
    r2_1 = {
      keys = {},
      puzzle = {},
      food = {
        {
          id = "canned_soup",
          name = "Canned soup"
        }
      },
      rest = {}
    },
    r3_1 = {
      keys = {},
      puzzle = {
        {
          id = "fuse",
          name = "Glass fuse",
          clue = "Someone wrote 'east of the water' and stopped."
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
          name = "Almond water"
        }
      },
      rest = {}
    },
    r2_2 = {
      keys = {
        {
          id = "small_key",
          name = "Small brass key"
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
          name = "Green valve",
          clue = "A tag reads: third hiss, then the latch."
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
      id = "hall_static",
      name = "The Hall Static",
      patrol = {
        "r2_0",
        "r3_0",
        "r3_1"
      },
      damage = 20,
      visualClass = "/Game/Entities/Smiler/BP_SmilerCharacter.BP_SmilerCharacter_C"
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
  seed = 1360
}
