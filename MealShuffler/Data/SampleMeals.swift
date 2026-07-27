import Foundation

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
                .init(name: L10n.string("Lemon"), quantity: 1, unit: "pcs", aisle: .produce)
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
                .init(name: L10n.string("Soy sauce"), quantity: 1, unit: "bottle", aisle: .pantry)
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
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "Taco",
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
                .init(name: L10n.string("Rice"), quantity: 300, unit: "g", aisle: .pantry)
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
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: "Spaghetti bolognese",
            subtitle: L10n.string("A reliable weeknight classic"),
            emoji: "🍝",
            prepMinutes: 35,
            tags: [.meat, .pasta],
            ingredients: [
                .init(name: L10n.string("Minced beef"), quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: L10n.string("Spaghetti"), quantity: 400, unit: "g", aisle: .pantry),
                .init(name: L10n.string("Chopped tomatoes"), quantity: 2, unit: "can", aisle: .pantry),
                .init(name: L10n.string("Carrots"), quantity: 2, unit: "pcs", aisle: .produce),
                .init(name: L10n.string("Yellow onion"), quantity: 1, unit: "pcs", aisle: .produce)
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
                .init(name: L10n.string("Bread"), quantity: 1, unit: "pcs", aisle: .bread)
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
            ]
        )
    ]
}
