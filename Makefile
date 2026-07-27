.PHONY: bootstrap test open

bootstrap:
	bash ci/bootstrap-ios.sh

test: bootstrap
	bash ci/test-ios.sh

open: bootstrap
	open MealShuffler.xcodeproj
