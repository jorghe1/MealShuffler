import XCTest

/// Every other tab once: Meals and its add sheet, Shop, Family with its rules and settings.
final class TabsSmokeTests: SmokeTestCase {
    override var flowName: String { "tabs" }

    @MainActor
    func testMealsShopFamilyRulesAndSettings() {
        launch(skipOnboarding: true)
        assertMainTabsVisible()

        step("Meals") {
            guard openTab("Meals") else { return }
            _ = firstExisting([app.navigationBars["Meals"]], timeout: 5)
            pause(1)
            screenshot("meals")

            let opened = tapFirst([
                app.buttons["meals.add"],
                app.navigationBars["Meals"].buttons["Add recipe"],
                app.buttons["Add recipe"],
            ], "Add recipe button")
            guard opened else { return }
            if firstExisting([app.navigationBars["Add recipe"], app.buttons["Write it yourself"]], timeout: 5) == nil {
                note("Add recipe sheet did not appear")
            }
            pause(0.8)
            screenshot("meals-add-sheet")
            dismissSheet(using: [
                app.buttons["addRecipe.cancel"],
                app.navigationBars["Add recipe"].buttons["Cancel"],
                app.buttons["Cancel"],
            ])
        }

        step("Shop") {
            guard openTab("Shop") else { return }
            _ = firstExisting([app.navigationBars["Shopping list"]], timeout: 5)
            pause(1)
            screenshot("shop")
        }

        step("Family") {
            guard openTab("Family") else { return }
            _ = firstExisting([app.navigationBars["Family"]], timeout: 5)
            pause(1)
            screenshot("family")
        }

        step("Rules") {
            let allRulesByLabel = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "All ", " rules"))
                .firstMatch
            var found = firstExisting([
                app.buttons["family.allRules"],
                allRulesByLabel,
                app.buttons["Write your first rule"],
            ], timeout: 3)
            if found == nil, scrollUntilExists(allRulesByLabel) {
                // Below the household card and four rule rows on a small phone.
                found = allRulesByLabel
            }
            guard let allRules = found else {
                note("Rules link not found in Family")
                return
            }
            tap(allRules)
            _ = firstExisting([app.navigationBars["House rules"]], timeout: 5)
            pause(1)
            screenshot("rules")

            let field = firstExisting([
                app.textFields["rules.composerField"],
                app.textFields["Taco Friday, fish twice a week…"],
                app.textFields.firstMatch,
            ], timeout: 5)
            if let field {
                tap(field)
                field.typeText("laks på torsdag")
                // "laks" can mean salmon or any fish, so the composer asks which.
                if !staticText(containing: "What do you mean by").waitForExistence(timeout: 4) {
                    note("Rule clarification did not appear")
                }
                pause(0.8)
                screenshot("rules-clarification")
                // Nothing is saved until "Add rule" or return; leaving the screen discards it.
            } else {
                note("Rule text field not found")
            }
            goBack(to: "Family")
            pause(0.8)
        }

        step("Settings") {
            let opened = tapFirst([
                app.buttons["family.settings"],
                app.navigationBars["Family"].buttons["Settings"],
                app.buttons["Settings"],
            ], "Settings gear", timeout: 8)
            guard opened else { return }
            _ = firstExisting([app.navigationBars["Settings"]], timeout: 5)
            pause(1)
            screenshot("settings")
            goBack(to: "Family")
        }
    }
}
