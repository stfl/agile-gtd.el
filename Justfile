default:
    @just --list

build:
    eask recompile

test:
    eask run script test

lint:
    eask lint package agile-gtd.el
