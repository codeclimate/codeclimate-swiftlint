FROM norionomura/swift:403

LABEL maintainer="Code Climate <hello@codeclimate.com>"

WORKDIR /usr/src/

RUN git clone --depth 1 https://github.com/realm/SwiftLint.git

RUN cd SwiftLint && swift build -v -c release && \
    cp "$(swift build -c release --show-bin-path)/codeclimate-SwiftLint" /usr/local/bin && \
    cd .. && rm -rf SwiftLint

COPY engine.json ./engine.json.template
RUN sed s/xxx_SwiftLintVersion_xxx/`./codeclimate-SwiftLint --version`/ engine.json.template > engine.json

RUN adduser --quiet --no-create-home --uid 9000 --disabled-password app

#USER app
WORKDIR /code
VOLUME /code

CMD ["/usr/local/bin/codeclimate-SwiftLint"]

