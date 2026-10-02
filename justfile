mmdc_flags := "-q -c diagrams/mermaid-config.json -p diagrams/puppeteer-config.json"

default: build

build: slides

diagrams:
    for f in diagrams/*.mmd; do mmdc {{mmdc_flags}} -i "$f" -o "${f%.mmd}.svg" || exit 1; done

slides: diagrams
    mkdir -p build
    pandoc slides.md -t revealjs -s --slide-level=2 -V theme=simple --highlight-style=tango --css custom.css --embed-resources -o build/slides.html

clean:
    rm -rf build diagrams/*.svg
