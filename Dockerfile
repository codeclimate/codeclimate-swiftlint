FROM norionomura/swift:403

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

COPY engine.json /engine.json.template
RUN sed s/xxx_SwiftLintVersion_xxx/`codeclimate-SwiftLint --version`/ /engine.json.template > /engine.json && rm /engine.json.template

RUN yes | adduser --quiet --no-create-home --uid 9000 --disabled-password app

#USER app
WORKDIR /code
VOLUME /code

CMD ["/usr/local/bin/codeclimate-SwiftLint"]

