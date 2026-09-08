import Foundation

/// The meals a household starts with.
///
/// Every one carries instructions. They did not before, which meant Cook Mode -- a
/// full-screen feature with step progress, ingredient scaling and a screen that stays
/// awake -- answered "No steps saved for this meal" for every default meal, so nobody saw
/// it work until they imported a recipe of their own.
///
/// Forty rather than fourteen, because the starter rules ask for fish twice a week and a
/// pizza on Saturday. Against three fish meals and one pizza that made most of the week
/// deterministic and the rest repetitive by the third week: the generator was never the
/// bottleneck, the library was.
///
/// Ids 1-14 are the original meals and must keep their values -- favourites, history and
/// customised copies all reference them.
enum SampleMeals {
    static let all: [Meal] = [
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: L10n.string("Baked salmon with roasted vegetables"),
            subtitle: L10n.string("Lemon, potatoes and herbs"),
            emoji: "🐟",
            prepMinutes: 35,
            tags: [.fish],
            ingredients: [
                .init(name: L10n.string("Salmon fillet"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Broccoli"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Lemon"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Olive oil"), quantity: 1, unit: "bottle", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Heat the oven to 200°C."),
                L10n.string("Cut the potatoes into wedges, toss with oil and salt, and roast for 20 minutes."),
                L10n.string("Add the salmon and broccoli to the tray and season."),
                L10n.string("Roast for 12–15 minutes, until the salmon flakes easily."),
                L10n.string("Squeeze the lemon over everything and serve.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: L10n.string("Fish tacos"),
            subtitle: L10n.string("Crispy cod and fresh cabbage slaw"),
            emoji: "🌮",
            prepMinutes: 30,
            tags: [.fish, .taco],
            ingredients: [
                .init(name: L10n.string("Cod fillet"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Tortilla wraps"), quantity: 8, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Red cabbage"), quantity: 0.5, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Sour cream"), quantity: 1, unit: "tub", aisle: .dairy),
                .init(name: L10n.string("Lime"), quantity: 2, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Cut the cod into strips and season with salt and pepper."),
                L10n.string("Fry the fish for 2–3 minutes on each side until golden."),
                L10n.string("Shred the cabbage finely and mix with lime juice and a pinch of salt."),
                L10n.string("Warm the tortillas in a dry pan."),
                L10n.string("Fill with fish and slaw, and top with sour cream.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: L10n.string("Chicken stir-fry"),
            subtitle: L10n.string("Vegetables, noodles and ginger"),
            emoji: "🥢",
            prepMinutes: 25,
            tags: [.chicken, .quick],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Egg noodles"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Stir-fry vegetables"), quantity: 1, unit: "bag", aisle: .frozen),
                .init(name: L10n.string("Soy sauce"), quantity: 1, unit: "bottle", aisle: .pantry),
                .init(name: L10n.string("Ginger"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Boil the noodles as the packet says, then drain."),
                L10n.string("Cut the chicken into strips and fry over high heat for 5 minutes."),
                L10n.string("Add the vegetables and grated ginger, and fry for 3 minutes more."),
                L10n.string("Stir in the noodles and soy sauce and serve straight away.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: L10n.string("Creamy chicken pasta"),
            subtitle: L10n.string("Spinach and Parmesan"),
            emoji: "🍝",
            prepMinutes: 30,
            tags: [.chicken, .pasta],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Pasta"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Cooking cream"), quantity: 3, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Spinach"), quantity: 200, unit: "g", aisle: .produce),
                .init(name: L10n.string("Parmesan"), quantity: 100, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Boil the pasta in well-salted water."),
                L10n.string("Cut the chicken into cubes and fry until golden."),
                L10n.string("Pour in the cream and let it simmer for 5 minutes."),
                L10n.string("Stir in the spinach until it wilts."),
                L10n.string("Toss with the pasta and finish with grated Parmesan.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: L10n.string("Margherita pizza"),
            subtitle: L10n.string("Tomato, mozzarella and basil"),
            emoji: "🍕",
            prepMinutes: 45,
            tags: [.pizza, .vegetarian, .weekend],
            ingredients: [
                .init(name: L10n.string("Pizza dough"), quantity: 2, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Pizza sauce"), quantity: 1, unit: "jar", aisle: .pantry),
                .init(name: L10n.string("Mozzarella"), quantity: 300, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Basil"), quantity: 1, unit: "pot", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven as hot as it goes, with a tray inside."),
                L10n.string("Roll the dough out thin."),
                L10n.string("Spread on the sauce and tear the mozzarella over."),
                L10n.string("Bake for 8–10 minutes until the edges blister."),
                L10n.string("Scatter fresh basil over just before serving.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: L10n.string("Taco"),
            subtitle: L10n.string("The classic family favorite"),
            emoji: "🌮",
            prepMinutes: 25,
            tags: [.meat, .taco, .quick],
            ingredients: [
                .init(name: L10n.string("Minced beef"), quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Tortilla wraps"), quantity: 8, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Taco seasoning"), quantity: 1, unit: "bag", aisle: .pantry),
                .init(name: L10n.string("Corn"), quantity: 1, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Tomatoes"), quantity: 4, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Grated cheese"), quantity: 200, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Brown the mince in a hot pan."),
                L10n.string("Stir in the seasoning and a splash of water, and simmer for 5 minutes."),
                L10n.string("Dice the tomatoes and drain the corn."),
                L10n.string("Warm the tortillas and put everything on the table.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            name: L10n.string("Lentil curry"),
            subtitle: L10n.string("Coconut milk, tomato and warming spices"),
            emoji: "🍛",
            prepMinutes: 30,
            tags: [.vegetarian],
            ingredients: [
                .init(name: L10n.string("Red lentils"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Coconut milk"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Curry powder"), quantity: 1, unit: "bag", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Fry the chopped onion soft, then add the curry powder."),
                L10n.string("Add the lentils, tomatoes and coconut milk."),
                L10n.string("Simmer for 20 minutes, until the lentils are soft."),
                L10n.string("Season with salt and serve over the rice.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            name: L10n.string("Tomato soup with egg"),
            subtitle: L10n.string("Quick, warm and simple"),
            emoji: "🥣",
            prepMinutes: 20,
            tags: [.vegetarian, .soup, .quick],
            ingredients: [
                .init(name: L10n.string("Chopped tomatoes"), quantity: 3, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Eggs"), quantity: 4, unit: "pcs", aisle: .dairy),
                .init(name: L10n.string("Cooking cream"), quantity: 2, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Bread"), quantity: 1, unit: "pcs", aisle: .bread)
            ],
            instructions: [
                L10n.string("Boil the eggs for 8 minutes, then cool and peel them."),
                L10n.string("Fry the chopped onion soft in a pot."),
                L10n.string("Add the tomatoes and simmer for 10 minutes."),
                L10n.string("Stir in the cream and blend smooth if you like."),
                L10n.string("Serve with halved eggs and bread.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: L10n.string("Spaghetti bolognese"),
            subtitle: L10n.string("A reliable weeknight classic"),
            emoji: "🍝",
            prepMinutes: 35,
            tags: [.meat, .pasta],
            ingredients: [
                .init(name: L10n.string("Minced beef"), quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Spaghetti"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Carrots"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Garlic"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Finely chop the onion, carrot and garlic."),
                L10n.string("Brown the mince, then add the vegetables and fry for 5 minutes."),
                L10n.string("Add the tomatoes and simmer for 20 minutes."),
                L10n.string("Boil the spaghetti while the sauce reduces."),
                L10n.string("Season well with salt and pepper before serving.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: L10n.string("Cauliflower soup"),
            subtitle: L10n.string("Creamy soup with a crispy topping"),
            emoji: "🥣",
            prepMinutes: 25,
            tags: [.vegetarian, .soup, .quick],
            ingredients: [
                .init(name: L10n.string("Cauliflower"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Potatoes"), quantity: 300, unit: "g", aisle: .produce),
                .init(name: L10n.string("Cooking cream"), quantity: 3, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Bread"), quantity: 1, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Stock cube"), quantity: 1, unit: "pcs", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Cut the cauliflower and potatoes into rough pieces."),
                L10n.string("Boil them in stock until soft, about 15 minutes."),
                L10n.string("Blend smooth and stir in the cream."),
                L10n.string("Toast the bread and serve alongside.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: L10n.string("Chicken pita"),
            subtitle: L10n.string("Salad, dressing and warm pita bread"),
            emoji: "🥙",
            prepMinutes: 25,
            tags: [.chicken, .quick],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Pita bread"), quantity: 6, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Romaine lettuce"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Cucumber"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Plain yogurt"), quantity: 1, unit: "tub", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Cut the chicken into strips and season."),
                L10n.string("Fry for 6–8 minutes until cooked through."),
                L10n.string("Slice the lettuce and cucumber."),
                L10n.string("Warm the pitas and fill them with everything."),
                L10n.string("Finish with a spoon of yogurt.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: L10n.string("Veggie burger"),
            subtitle: L10n.string("Crispy oven potatoes and salad"),
            emoji: "🍔",
            prepMinutes: 35,
            tags: [.vegetarian, .weekend],
            ingredients: [
                .init(name: L10n.string("Veggie burgers"), quantity: 4, unit: "pcs", aisle: .frozen),
                .init(name: L10n.string("Burger buns"), quantity: 4, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Romaine lettuce"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Tomatoes"), quantity: 2, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven to 220°C."),
                L10n.string("Cut the potatoes into wedges and roast for 25 minutes."),
                L10n.string("Fry the burgers according to the packet."),
                L10n.string("Toast the buns and slice the tomato."),
                L10n.string("Build the burgers and serve with the potatoes.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            name: L10n.string("Fish gratin"),
            subtitle: L10n.string("With carrot slaw and boiled potatoes"),
            emoji: "🐟",
            prepMinutes: 40,
            tags: [.fish],
            ingredients: [
                .init(name: L10n.string("Fish gratin"), quantity: 1, unit: "pcs", aisle: .frozen),
                .init(name: L10n.string("Potatoes"), quantity: 700, unit: "g", aisle: .produce),
                .init(name: L10n.string("Carrots"), quantity: 4, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Lemon"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven to 200°C and bake the gratin as the packet says."),
                L10n.string("Boil the potatoes until tender."),
                L10n.string("Grate the carrots and dress them with lemon juice."),
                L10n.string("Serve everything together.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            name: L10n.string("Meatballs in tomato sauce"),
            subtitle: L10n.string("With mashed potatoes and green peas"),
            emoji: "🍲",
            prepMinutes: 35,
            tags: [.meat],
            ingredients: [
                .init(name: L10n.string("Meatballs"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 900, unit: "g", aisle: .produce),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Green peas"), quantity: 1, unit: "bag", aisle: .frozen),
                .init(name: L10n.string("Milk"), quantity: 3, unit: "dl", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Boil the potatoes until soft."),
                L10n.string("Brown the meatballs in a pan."),
                L10n.string("Add the tomatoes and simmer for 10 minutes."),
                L10n.string("Mash the potatoes with warm milk and butter."),
                L10n.string("Warm the peas and serve.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            name: L10n.string("Carbonara"),
            subtitle: L10n.string("Bacon, egg and lots of Parmesan"),
            emoji: "🍝",
            prepMinutes: 20,
            tags: [.meat, .pasta, .quick],
            ingredients: [
                .init(name: L10n.string("Spaghetti"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Bacon"), quantity: 200, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Eggs"), quantity: 4, unit: "pcs", aisle: .dairy),
                .init(name: L10n.string("Parmesan"), quantity: 100, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Garlic"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Boil the spaghetti in well-salted water."),
                L10n.string("Fry the bacon crisp with the crushed garlic."),
                L10n.string("Whisk the eggs with the grated Parmesan and plenty of pepper."),
                L10n.string("Drain the pasta, keeping a cup of the water."),
                L10n.string("Take the pan off the heat, stir everything together, and loosen with the pasta water.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            name: L10n.string("Lasagne"),
            subtitle: L10n.string("Worth the extra half hour"),
            emoji: "🍝",
            prepMinutes: 60,
            tags: [.meat, .pasta, .weekend],
            ingredients: [
                .init(name: L10n.string("Minced beef"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Lasagne sheets"), quantity: 1, unit: "bag", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Milk"), quantity: 5, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Grated cheese"), quantity: 200, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Brown the mince with the chopped onion."),
                L10n.string("Add the tomatoes and simmer for 15 minutes."),
                L10n.string("Make a white sauce from the butter, a little flour and the milk."),
                L10n.string("Layer meat sauce, sheets and white sauce in a dish."),
                L10n.string("Top with cheese and bake at 200°C for 30 minutes."),
                L10n.string("Let it rest for 10 minutes before cutting.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            name: L10n.string("Pasta with tomato and basil"),
            subtitle: L10n.string("Five ingredients, twenty minutes"),
            emoji: "🍅",
            prepMinutes: 20,
            tags: [.vegetarian, .pasta, .quick],
            ingredients: [
                .init(name: L10n.string("Pasta"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Garlic"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Basil"), quantity: 1, unit: "pot", aisle: .produce),
                .init(name: L10n.string("Olive oil"), quantity: 1, unit: "bottle", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Boil the pasta in well-salted water."),
                L10n.string("Fry the sliced garlic gently in the oil."),
                L10n.string("Add the tomatoes and simmer for 10 minutes."),
                L10n.string("Toss the pasta through the sauce and tear the basil over.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            name: L10n.string("Chicken fajitas"),
            subtitle: L10n.string("Peppers, onion and warm tortillas"),
            emoji: "🌯",
            prepMinutes: 25,
            tags: [.chicken, .taco, .quick],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Bell pepper"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Red onion"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Tortilla wraps"), quantity: 8, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Taco seasoning"), quantity: 1, unit: "bag", aisle: .pantry),
                .init(name: L10n.string("Sour cream"), quantity: 1, unit: "tub", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Slice the chicken, peppers and onion into strips."),
                L10n.string("Fry the chicken over high heat for 5 minutes."),
                L10n.string("Add the vegetables and the seasoning, and fry for 5 minutes more."),
                L10n.string("Warm the tortillas and serve with sour cream.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            name: L10n.string("Chili con carne"),
            subtitle: L10n.string("Better the next day"),
            emoji: "🌶️",
            prepMinutes: 40,
            tags: [.meat],
            ingredients: [
                .init(name: L10n.string("Minced beef"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Kidney beans"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Yellow onion"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Chili powder"), quantity: 1, unit: "bag", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Brown the mince with the chopped onion."),
                L10n.string("Stir in the chili powder and cook for a minute."),
                L10n.string("Add the tomatoes and beans, and simmer for 25 minutes."),
                L10n.string("Season and serve over the rice.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            name: L10n.string("Butter chicken"),
            subtitle: L10n.string("Mild, creamy and popular with everyone"),
            emoji: "🍛",
            prepMinutes: 35,
            tags: [.chicken],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 1, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Cooking cream"), quantity: 3, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Curry powder"), quantity: 1, unit: "bag", aisle: .pantry),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Cube the chicken and fry it in the butter."),
                L10n.string("Add the chopped onion and the curry powder."),
                L10n.string("Pour in the tomatoes and cream, and simmer for 15 minutes."),
                L10n.string("Season with salt and serve with the rice.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            name: L10n.string("Thai red curry with chicken"),
            subtitle: L10n.string("Coconut milk and a bit of heat"),
            emoji: "🥥",
            prepMinutes: 30,
            tags: [.chicken],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Coconut milk"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Red curry paste"), quantity: 1, unit: "jar", aisle: .pantry),
                .init(name: L10n.string("Bell pepper"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Fresh coriander"), quantity: 1, unit: "pot", aisle: .produce)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Fry the curry paste in a hot pot for a minute."),
                L10n.string("Add the cubed chicken and brown it."),
                L10n.string("Pour in the coconut milk and add the sliced pepper."),
                L10n.string("Simmer for 15 minutes and finish with coriander.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            name: L10n.string("Fried rice with egg"),
            subtitle: L10n.string("Uses whatever is in the fridge"),
            emoji: "🍚",
            prepMinutes: 20,
            tags: [.vegetarian, .quick],
            ingredients: [
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Eggs"), quantity: 4, unit: "pcs", aisle: .dairy),
                .init(name: L10n.string("Stir-fry vegetables"), quantity: 1, unit: "bag", aisle: .frozen),
                .init(name: L10n.string("Soy sauce"), quantity: 1, unit: "bottle", aisle: .pantry),
                .init(name: L10n.string("Spring onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Boil the rice and let it cool a little."),
                L10n.string("Scramble the eggs in a hot pan and set them aside."),
                L10n.string("Fry the vegetables over high heat for 3 minutes."),
                L10n.string("Add the rice and soy sauce, and fry for 3 minutes more."),
                L10n.string("Stir the egg back in and scatter spring onion over.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            name: L10n.string("Teriyaki salmon with rice"),
            subtitle: L10n.string("Sticky, sweet and on the table fast"),
            emoji: "🍣",
            prepMinutes: 25,
            tags: [.fish, .quick],
            ingredients: [
                .init(name: L10n.string("Salmon fillet"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Teriyaki sauce"), quantity: 1, unit: "bottle", aisle: .pantry),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Broccoli"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Spring onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Fry the salmon skin-side down for 4 minutes."),
                L10n.string("Turn it, pour over the teriyaki, and cook for 3 minutes more."),
                L10n.string("Steam the broccoli until just tender."),
                L10n.string("Serve on the rice with spring onion on top.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
            name: L10n.string("Beef burgers"),
            subtitle: L10n.string("Saturday food that takes half an hour"),
            emoji: "🍔",
            prepMinutes: 30,
            tags: [.meat, .weekend],
            ingredients: [
                .init(name: L10n.string("Beef patties"), quantity: 4, unit: "pcs", aisle: .meatAndFish),
                .init(name: L10n.string("Burger buns"), quantity: 4, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Tomatoes"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Romaine lettuce"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Grated cheese"), quantity: 100, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Heat the oven to 220°C and roast potato wedges for 25 minutes."),
                L10n.string("Season the patties well and fry for 4 minutes on each side."),
                L10n.string("Add cheese to melt over the last minute."),
                L10n.string("Toast the buns and slice the tomato and lettuce."),
                L10n.string("Build and serve with the potatoes.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
            name: L10n.string("Pepperoni pizza"),
            subtitle: L10n.string("The one everyone agrees on"),
            emoji: "🍕",
            prepMinutes: 45,
            tags: [.pizza, .meat, .weekend],
            ingredients: [
                .init(name: L10n.string("Pizza dough"), quantity: 2, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Pizza sauce"), quantity: 1, unit: "jar", aisle: .pantry),
                .init(name: L10n.string("Grated cheese"), quantity: 300, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Pepperoni"), quantity: 150, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Red onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven as hot as it goes, with a tray inside."),
                L10n.string("Roll the dough out thin and spread on the sauce."),
                L10n.string("Add cheese, pepperoni and thinly sliced onion."),
                L10n.string("Bake for 8–10 minutes until the edges are dark at the tips.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
            name: L10n.string("Roast chicken thighs with potatoes"),
            subtitle: L10n.string("One tray, almost no work"),
            emoji: "🍗",
            prepMinutes: 55,
            tags: [.chicken, .weekend],
            ingredients: [
                .init(name: L10n.string("Chicken thighs"), quantity: 8, unit: "pcs", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 900, unit: "g", aisle: .produce),
                .init(name: L10n.string("Carrots"), quantity: 4, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Garlic"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Olive oil"), quantity: 1, unit: "bottle", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Heat the oven to 200°C."),
                L10n.string("Cut the potatoes and carrots into chunks and spread on a tray."),
                L10n.string("Lay the chicken on top, add whole garlic cloves, and season well."),
                L10n.string("Roast for 40–45 minutes until the skin is crisp."),
                L10n.string("Spoon the tray juices over before serving.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000027")!,
            name: L10n.string("Pan-fried cod with potatoes"),
            subtitle: L10n.string("Butter, lemon and boiled potatoes"),
            emoji: "🐟",
            prepMinutes: 30,
            tags: [.fish],
            ingredients: [
                .init(name: L10n.string("Cod fillet"), quantity: 700, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Butter"), quantity: 75, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Lemon"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Carrots"), quantity: 3, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Boil the potatoes and carrots until tender."),
                L10n.string("Pat the cod dry and season it with salt."),
                L10n.string("Fry in butter for 3–4 minutes on each side."),
                L10n.string("Let the butter brown, then squeeze in the lemon."),
                L10n.string("Spoon the butter over the fish and serve.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000028")!,
            name: L10n.string("Fish cakes with potatoes"),
            subtitle: L10n.string("The fastest fish day there is"),
            emoji: "🐟",
            prepMinutes: 20,
            tags: [.fish, .quick],
            ingredients: [
                .init(name: L10n.string("Fish cakes"), quantity: 8, unit: "pcs", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Carrots"), quantity: 4, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Boil the potatoes until tender."),
                L10n.string("Grate the carrots into a slaw."),
                L10n.string("Fry the fish cakes in butter until golden on both sides."),
                L10n.string("Serve with the potatoes and slaw.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000029")!,
            name: L10n.string("Sausages with mashed potatoes"),
            subtitle: L10n.string("Nobody has ever complained"),
            emoji: "🌭",
            prepMinutes: 25,
            tags: [.meat, .quick],
            ingredients: [
                .init(name: L10n.string("Sausages"), quantity: 8, unit: "pcs", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 900, unit: "g", aisle: .produce),
                .init(name: L10n.string("Milk"), quantity: 2, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Green peas"), quantity: 1, unit: "bag", aisle: .frozen)
            ],
            instructions: [
                L10n.string("Boil the potatoes until soft."),
                L10n.string("Fry or boil the sausages."),
                L10n.string("Mash the potatoes with warm milk and butter."),
                L10n.string("Warm the peas and serve everything together.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            name: L10n.string("Pork chops with apple"),
            subtitle: L10n.string("Sweet apple against salty pork"),
            emoji: "🍎",
            prepMinutes: 35,
            tags: [.meat],
            ingredients: [
                .init(name: L10n.string("Pork chops"), quantity: 4, unit: "pcs", aisle: .meatAndFish),
                .init(name: L10n.string("Apple"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Potatoes"), quantity: 800, unit: "g", aisle: .produce),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Boil the potatoes until tender."),
                L10n.string("Season the chops and fry them for 5 minutes on each side."),
                L10n.string("Set the meat aside and fry apple wedges and onion in the same pan."),
                L10n.string("Return the chops to warm through, and serve.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            name: L10n.string("Chicken noodle soup"),
            subtitle: L10n.string("What you want when someone is poorly"),
            emoji: "🍜",
            prepMinutes: 30,
            tags: [.chicken, .soup],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 400, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Egg noodles"), quantity: 200, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Carrots"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Celery"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Stock cube"), quantity: 2, unit: "pcs", aisle: .pantry),
                .init(name: L10n.string("Spring onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Bring 2 litres of stock to the boil."),
                L10n.string("Add sliced carrot and celery, and simmer for 10 minutes."),
                L10n.string("Add the sliced chicken and cook for 6 minutes."),
                L10n.string("Add the noodles for the last 4 minutes."),
                L10n.string("Scatter spring onion over each bowl.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
            name: L10n.string("Minestrone"),
            subtitle: L10n.string("A pot of vegetables and beans"),
            emoji: "🥣",
            prepMinutes: 30,
            tags: [.vegetarian, .soup],
            ingredients: [
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Kidney beans"), quantity: 1, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Carrots"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Celery"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Pasta"), quantity: 150, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Stock cube"), quantity: 2, unit: "pcs", aisle: .pantry),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Dice the onion, carrot and celery and fry them soft."),
                L10n.string("Add the tomatoes and 1 litre of stock."),
                L10n.string("Simmer for 15 minutes."),
                L10n.string("Add the pasta and beans, and cook until the pasta is done."),
                L10n.string("Season well and serve.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            name: L10n.string("Halloumi wraps"),
            subtitle: L10n.string("Salty cheese, crunchy salad"),
            emoji: "🧀",
            prepMinutes: 20,
            tags: [.vegetarian, .quick],
            ingredients: [
                .init(name: L10n.string("Halloumi"), quantity: 400, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Tortilla wraps"), quantity: 8, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Cucumber"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Tomatoes"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Plain yogurt"), quantity: 1, unit: "tub", aisle: .dairy),
                .init(name: L10n.string("Romaine lettuce"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Slice the halloumi about a centimetre thick."),
                L10n.string("Fry it dry for 2 minutes on each side until golden."),
                L10n.string("Chop the cucumber, tomato and lettuce."),
                L10n.string("Warm the tortillas and fill them."),
                L10n.string("Finish with a spoon of yogurt.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034")!,
            name: L10n.string("Falafel with couscous"),
            subtitle: L10n.string("Ready faster than the couscous swells"),
            emoji: "🧆",
            prepMinutes: 30,
            tags: [.vegetarian],
            ingredients: [
                .init(name: L10n.string("Falafel"), quantity: 16, unit: "pcs", aisle: .frozen),
                .init(name: L10n.string("Couscous"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Cucumber"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Tomatoes"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Feta"), quantity: 150, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Lemon"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven to 200°C and bake the falafel for 15 minutes."),
                L10n.string("Pour boiling water over the couscous and cover it for 5 minutes."),
                L10n.string("Dice the cucumber and tomato and fold them through."),
                L10n.string("Crumble the feta over and squeeze in the lemon.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000035")!,
            name: L10n.string("Pizza with ham and mushroom"),
            subtitle: L10n.string("The grown-up one"),
            emoji: "🍕",
            prepMinutes: 45,
            tags: [.pizza, .meat, .weekend],
            ingredients: [
                .init(name: L10n.string("Pizza dough"), quantity: 2, unit: "pcs", aisle: .bread),
                .init(name: L10n.string("Pizza sauce"), quantity: 1, unit: "jar", aisle: .pantry),
                .init(name: L10n.string("Grated cheese"), quantity: 300, unit: "g", aisle: .dairy),
                .init(name: L10n.string("Cooked ham"), quantity: 150, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Mushrooms"), quantity: 250, unit: "g", aisle: .produce)
            ],
            instructions: [
                L10n.string("Heat the oven as hot as it goes, with a tray inside."),
                L10n.string("Slice the mushrooms thinly."),
                L10n.string("Roll out the dough, spread the sauce, and add cheese, ham and mushrooms."),
                L10n.string("Bake for 8–10 minutes.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000036")!,
            name: L10n.string("Shepherd's pie"),
            subtitle: L10n.string("Mince under a potato lid"),
            emoji: "🥧",
            prepMinutes: 55,
            tags: [.meat, .weekend],
            ingredients: [
                .init(name: L10n.string("Minced lamb"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Potatoes"), quantity: 1, unit: "kg", aisle: .produce),
                .init(name: L10n.string("Carrots"), quantity: 3, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Green peas"), quantity: 1, unit: "bag", aisle: .frozen),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Milk"), quantity: 2, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Boil the potatoes and mash them with milk and butter."),
                L10n.string("Brown the mince with the chopped onion and diced carrot."),
                L10n.string("Add the peas and a little water, and simmer for 10 minutes."),
                L10n.string("Spread the mince in a dish and cover with the mash."),
                L10n.string("Bake at 200°C for 25 minutes until the top is golden.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000037")!,
            name: L10n.string("Sweet and sour chicken"),
            subtitle: L10n.string("Takeaway, at home"),
            emoji: "🥡",
            prepMinutes: 30,
            tags: [.chicken],
            ingredients: [
                .init(name: L10n.string("Chicken breast"), quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Sweet and sour sauce"), quantity: 1, unit: "jar", aisle: .pantry),
                .init(name: L10n.string("Bell pepper"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Cube the chicken and fry it golden."),
                L10n.string("Add the pepper and onion in chunks, and fry for 4 minutes."),
                L10n.string("Pour over the sauce and simmer for 5 minutes."),
                L10n.string("Serve with the rice.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000038")!,
            name: L10n.string("Tuna pasta salad"),
            subtitle: L10n.string("No cooking beyond the pasta"),
            emoji: "🥗",
            prepMinutes: 15,
            tags: [.fish, .pasta, .quick],
            ingredients: [
                .init(name: L10n.string("Pasta"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Tuna"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Corn"), quantity: 1, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Cucumber"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Red onion"), quantity: 1, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Olive oil"), quantity: 1, unit: "bottle", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Boil the pasta and rinse it under cold water."),
                L10n.string("Drain the tuna and the corn."),
                L10n.string("Dice the cucumber and finely slice the onion."),
                L10n.string("Mix everything with the oil, salt and pepper.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000039")!,
            name: L10n.string("Vegetarian chili"),
            subtitle: L10n.string("Beans, not mince"),
            emoji: "🫘",
            prepMinutes: 35,
            tags: [.vegetarian],
            ingredients: [
                .init(name: L10n.string("Kidney beans"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Chickpeas"), quantity: 1, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Bell pepper"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Yellow onion"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Chili powder"), quantity: 1, unit: "bag", aisle: .pantry)
            ],
            instructions: [
                L10n.string("Put the rice on to boil."),
                L10n.string("Fry the chopped onion and diced pepper for 5 minutes."),
                L10n.string("Stir in the chili powder, then add the tomatoes."),
                L10n.string("Add the beans and chickpeas, and simmer for 20 minutes."),
                L10n.string("Season well and serve over the rice.")
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            name: L10n.string("Pancakes with bacon"),
            subtitle: L10n.string("Dinner that looks like pudding"),
            emoji: "🥞",
            prepMinutes: 25,
            tags: [.meat, .quick],
            ingredients: [
                .init(name: L10n.string("Plain flour"), quantity: 300, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Eggs"), quantity: 4, unit: "pcs", aisle: .dairy),
                .init(name: L10n.string("Milk"), quantity: 6, unit: "dl", aisle: .dairy),
                .init(name: L10n.string("Bacon"), quantity: 200, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Butter"), quantity: 50, unit: "g", aisle: .dairy)
            ],
            instructions: [
                L10n.string("Whisk the flour, eggs, milk and a pinch of salt into a smooth batter."),
                L10n.string("Let the batter rest for 10 minutes."),
                L10n.string("Fry the bacon crisp and set it aside."),
                L10n.string("Fry thin pancakes in butter, a ladle at a time."),
                L10n.string("Serve with the bacon, and jam for anyone who wants it.")
            ]
        )
    ]
}
