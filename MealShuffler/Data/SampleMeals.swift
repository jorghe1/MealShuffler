import Foundation

enum SampleMeals {
    static let all: [Meal] = [
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Laks med ovnsgrønnsaker",
            subtitle: "Sitron, potet og urter",
            emoji: "🐟",
            prepMinutes: 35,
            tags: [.fish],
            ingredients: [
                .init(name: "Laksefilet", quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: "Poteter", quantity: 800, unit: "g", aisle: .produce),
                .init(name: "Brokkoli", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Sitron", quantity: 1, unit: "stk", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Fisketaco",
            subtitle: "Sprø torsk og frisk kålsalat",
            emoji: "🌮",
            prepMinutes: 30,
            tags: [.fish, .taco],
            ingredients: [
                .init(name: "Torskefilet", quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: "Tortillalefser", quantity: 8, unit: "stk", aisle: .bread),
                .init(name: "Rødkål", quantity: 0.5, unit: "stk", aisle: .produce),
                .init(name: "Rømme", quantity: 1, unit: "beger", aisle: .dairy),
                .init(name: "Lime", quantity: 2, unit: "stk", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Kyllingwok",
            subtitle: "Grønnsaker, nudler og ingefær",
            emoji: "🥢",
            prepMinutes: 25,
            tags: [.chicken, .quick],
            ingredients: [
                .init(name: "Kyllingfilet", quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: "Eggnudler", quantity: 300, unit: "g", aisle: .pantry),
                .init(name: "Wokgrønnsaker", quantity: 1, unit: "pose", aisle: .frozen),
                .init(name: "Soyasaus", quantity: 1, unit: "flaske", aisle: .pantry)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Kremet kyllingpasta",
            subtitle: "Spinat og parmesan",
            emoji: "🍝",
            prepMinutes: 30,
            tags: [.chicken, .pasta],
            ingredients: [
                .init(name: "Kyllingfilet", quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: "Pasta", quantity: 400, unit: "g", aisle: .pantry),
                .init(name: "Matfløte", quantity: 3, unit: "dl", aisle: .dairy),
                .init(name: "Spinat", quantity: 200, unit: "g", aisle: .produce),
                .init(name: "Parmesan", quantity: 100, unit: "g", aisle: .dairy)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Margherita-pizza",
            subtitle: "Tomat, mozzarella og basilikum",
            emoji: "🍕",
            prepMinutes: 45,
            tags: [.pizza, .vegetarian, .weekend],
            ingredients: [
                .init(name: "Pizzadeig", quantity: 2, unit: "stk", aisle: .bread),
                .init(name: "Pizzasaus", quantity: 1, unit: "glass", aisle: .pantry),
                .init(name: "Mozzarella", quantity: 300, unit: "g", aisle: .dairy),
                .init(name: "Basilikum", quantity: 1, unit: "potte", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            name: "Taco",
            subtitle: "Den klassiske familiefavoritten",
            emoji: "🌮",
            prepMinutes: 25,
            tags: [.meat, .taco, .quick],
            ingredients: [
                .init(name: "Kjøttdeig", quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: "Tortillalefser", quantity: 8, unit: "stk", aisle: .bread),
                .init(name: "Tacokrydder", quantity: 1, unit: "pose", aisle: .pantry),
                .init(name: "Mais", quantity: 1, unit: "boks", aisle: .pantry),
                .init(name: "Tomater", quantity: 4, unit: "stk", aisle: .produce),
                .init(name: "Revet ost", quantity: 200, unit: "g", aisle: .dairy)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            name: "Linsegryte",
            subtitle: "Kokosmelk, tomat og varme krydder",
            emoji: "🍛",
            prepMinutes: 30,
            tags: [.vegetarian],
            ingredients: [
                .init(name: "Røde linser", quantity: 300, unit: "g", aisle: .pantry),
                .init(name: "Kokosmelk", quantity: 2, unit: "boks", aisle: .pantry),
                .init(name: "Hakkede tomater", quantity: 2, unit: "boks", aisle: .pantry),
                .init(name: "Gul løk", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Ris", quantity: 300, unit: "g", aisle: .pantry)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            name: "Tomatsuppe med egg",
            subtitle: "Rask, varm og enkel",
            emoji: "🥣",
            prepMinutes: 20,
            tags: [.vegetarian, .soup, .quick],
            ingredients: [
                .init(name: "Hakkede tomater", quantity: 3, unit: "boks", aisle: .pantry),
                .init(name: "Egg", quantity: 4, unit: "stk", aisle: .dairy),
                .init(name: "Matfløte", quantity: 2, unit: "dl", aisle: .dairy),
                .init(name: "Gul løk", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Brød", quantity: 1, unit: "stk", aisle: .bread)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            name: "Spaghetti bolognese",
            subtitle: "En trygg hverdagsklassiker",
            emoji: "🍝",
            prepMinutes: 35,
            tags: [.meat, .pasta],
            ingredients: [
                .init(name: "Kjøttdeig", quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: "Spaghetti", quantity: 400, unit: "g", aisle: .pantry),
                .init(name: "Hakkede tomater", quantity: 2, unit: "boks", aisle: .pantry),
                .init(name: "Gulrøtter", quantity: 2, unit: "stk", aisle: .produce),
                .init(name: "Gul løk", quantity: 1, unit: "stk", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Blomkålsuppe",
            subtitle: "Kremet suppe med sprø topping",
            emoji: "🥣",
            prepMinutes: 25,
            tags: [.vegetarian, .soup, .quick],
            ingredients: [
                .init(name: "Blomkål", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Poteter", quantity: 300, unit: "g", aisle: .produce),
                .init(name: "Matfløte", quantity: 3, unit: "dl", aisle: .dairy),
                .init(name: "Brød", quantity: 1, unit: "stk", aisle: .bread)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Kylling i pita",
            subtitle: "Salat, dressing og varme pitabrød",
            emoji: "🥙",
            prepMinutes: 25,
            tags: [.chicken, .quick],
            ingredients: [
                .init(name: "Kyllingfilet", quantity: 500, unit: "g", aisle: .meatAndFish),
                .init(name: "Pitabrød", quantity: 6, unit: "stk", aisle: .bread),
                .init(name: "Hjertesalat", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Agurk", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Yoghurt naturell", quantity: 1, unit: "beger", aisle: .dairy)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: "Vegetarburger",
            subtitle: "Sprø ovnspoteter og salat",
            emoji: "🍔",
            prepMinutes: 35,
            tags: [.vegetarian, .weekend],
            ingredients: [
                .init(name: "Vegetarburgere", quantity: 4, unit: "stk", aisle: .frozen),
                .init(name: "Burgerbrød", quantity: 4, unit: "stk", aisle: .bread),
                .init(name: "Poteter", quantity: 800, unit: "g", aisle: .produce),
                .init(name: "Hjertesalat", quantity: 1, unit: "stk", aisle: .produce),
                .init(name: "Tomater", quantity: 2, unit: "stk", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            name: "Fiskegrateng",
            subtitle: "Med råkost og kokte poteter",
            emoji: "🐟",
            prepMinutes: 40,
            tags: [.fish],
            ingredients: [
                .init(name: "Fiskegrateng", quantity: 1, unit: "stk", aisle: .frozen),
                .init(name: "Poteter", quantity: 700, unit: "g", aisle: .produce),
                .init(name: "Gulrøtter", quantity: 4, unit: "stk", aisle: .produce),
                .init(name: "Sitron", quantity: 1, unit: "stk", aisle: .produce)
            ]
        ),
        Meal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            name: "Kjøttboller i tomatsaus",
            subtitle: "Med potetmos og grønne erter",
            emoji: "🍲",
            prepMinutes: 35,
            tags: [.meat],
            ingredients: [
                .init(name: "Kjøttboller", quantity: 600, unit: "g", aisle: .meatAndFish),
                .init(name: "Poteter", quantity: 900, unit: "g", aisle: .produce),
                .init(name: "Hakkede tomater", quantity: 2, unit: "boks", aisle: .pantry),
                .init(name: "Grønne erter", quantity: 1, unit: "pose", aisle: .frozen),
                .init(name: "Melk", quantity: 3, unit: "dl", aisle: .dairy)
            ]
        )
    ]
}
