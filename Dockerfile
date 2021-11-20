FROM norionomura/swift:54 as build

LABEL maintainer="Code Climate <hello@codeclimate.com>"

WORKDIR /usr/src/codeclimate-SwiftLint

COPY Sources Sources/
COPY Package.* ./

RUN swift build -v -c release
RUN cp "$(swift build -c release --show-bin-path)/codeclimate-SwiftLint" /usr/local/bin

FROM ubuntu:16.04

RUN apt-get -q update && \
    apt-get -q install -y --no-install-recommends libatomic1 libicu55 libcurl3 libbsd0 libxml2


COPY engine.json /engine.json.template
COPY --from=build /usr/lib/swift/linux /usr/lib/swift/linux/
COPY --from=build /usr/local/bin/codeclimate-SwiftLint /usr/local/bin/
COPY --from=build /usr/lib/libsourcekitdInProc.so /usr/lib/

RUN sed s/xxx_SwiftLintVersion_xxx/`codeclimate-SwiftLint --version`/ /engine.json.template > /engine.json && rm /engine.json.template

RUN yes | adduser --quiet --no-create-home --uid 9000 --disabled-password app

USER app
WORKDIR /code
VOLUME /code

CMD ["/usr/local/bin/codeclimate-SwiftLint"]
