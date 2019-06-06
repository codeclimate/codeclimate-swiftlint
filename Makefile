.PHONY: image test

IMAGE_NAME ?= codeclimate/codeclimate-swiftlint

image:
	docker build -t $(IMAGE_NAME) .

test: image
	docker run -it --cap-drop all --rm -v `pwd`:/code -v `pwd`/config.json:/config.json $(IMAGE_NAME)
