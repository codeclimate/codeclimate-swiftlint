FROM norionomura/swift:403 as build

LABEL maintainer="Code Climate <hello@codeclimate.com>"

WORKDIR /usr/src/codeclimate-SwiftLint

COPY Sources Sources/
COPY Package.* ./
#to speedup resolve of dependencies
COPY .build/checkouts/ .build/checkouts/
COPY .build/repositories/ .build/repositories/
COPY .build/dependencies-state.json .build/dependencies-state.json

RUN swift build -v -c release && \
    cp "$(swift build -c release --show-bin-path)/codeclimate-SwiftLint" /usr/local/bin

FROM ubuntu:16.04

RUN apt-get -q update && \
    apt-get -q install -y --no-install-recommends libatomic1 libicu55 libcurl3 libbsd0 libxml2


COPY engine.json /engine.json.template
COPY --from=build /usr/lib/swift/linux /usr/lib/swift/linux/
COPY --from=build /usr/local/bin/codeclimate-SwiftLint /usr/local/bin/

RUN sed s/xxx_SwiftLintVersion_xxx/`codeclimate-SwiftLint --version`/ /engine.json.template > /engine.json && rm /engine.json.template

RUN yes | adduser --quiet --no-create-home --uid 9000 --disabled-password app

#USER app
WORKDIR /code
VOLUME /code

CMD ["/usr/local/bin/codeclimate-SwiftLint"]

