.PHONY: build-ApiFunction
build-ApiFunction:
	mkdir -p "$(ARTIFACTS_DIR)"
	cp aws_backend.py app.py "$(ARTIFACTS_DIR)/"
	python3 -m pip install --disable-pip-version-check -r requirements.txt --target "$(ARTIFACTS_DIR)"
