all: image test

image:
	docker build -t codeclimate-swiftlint .

test: image
	docker run -it --cap-drop all --rm -v `pwd`:/code -v `pwd`/config.json:/config.json codeclimate-swiftlint
