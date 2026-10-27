.PHONY: dmg run clean

dmg:
	@chmod +x ./build_dmg.sh
	@./build_dmg.sh

run:
	@swift run AgentSpur

clean:
	@swift package clean
	@rm -rf .build .dmg-build AgentSpur.dmg
