default: help

help:
    @just --list

setup:
    #!/usr/bin/env bash
    set -euo pipefail
    fail() { printf 'setup: %s\n' "$*" >&2; exit 1; }
    command -v asdf >/dev/null || fail "asdf 0.16.5 is required"
    [[ "$(asdf --version)" == "asdf version 0.16.5" ]] || fail "asdf 0.16.5 is required; found $(asdf --version)"

    plugins=(
      "erlang|https://github.com/asdf-vm/asdf-erlang.git"
      "elixir|https://github.com/asdf-vm/asdf-elixir.git"
      "java|https://github.com/halcyon/asdf-java.git"
      "just|https://github.com/olofvndrhr/asdf-just.git"
      "apalache|https://github.com/kokjinsam/asdf-apalache.git"
    )

    for entry in "${plugins[@]}"; do
      name="${entry%%|*}"
      expected_url="${entry#*|}"
      actual_url="$(asdf plugin list --urls | awk -v name="$name" '$1 == name { print $2 }')"
      if [[ -n "$actual_url" ]]; then
        [[ "$actual_url" == "$expected_url" ]] || fail "$name plugin URL mismatch: expected $expected_url, found $actual_url"
      else
        asdf plugin add "$name" "$expected_url"
      fi
    done

    while IFS=' ' read -r name version; do
      [[ -n "$name" && -n "$version" ]] || continue
      asdf install "$name" "$version"
    done < .tool-versions

doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    fail() { printf 'doctor: %s\n' "$*" >&2; exit 1; }
    command -v asdf >/dev/null || fail "asdf 0.16.5 is required"
    [[ "$(asdf --version)" == "asdf version 0.16.5" ]] || fail "asdf 0.16.5 is required; found $(asdf --version)"

    selected() {
      asdf current "$1" | awk -v name="$1" '$1 == name { print $2; exit }'
    }
    require_selection() {
      local tool="$1" expected="$2" actual
      actual="$(selected "$tool")"
      [[ "$actual" == "$expected" ]] || fail "$tool selection: expected $expected, found ${actual:-none}"
    }
    require_path() {
      local tool="$1" executable="$2" root path
      root="$(asdf where "$tool")"
      path="$(asdf which "$executable")"
      case "$path" in
        "$root"/*) ;;
        *) fail "$executable path $path is outside $root" ;;
      esac
    }

    require_selection erlang 27.0
    require_selection elixir 1.20.0-otp-27
    require_selection java temurin-17.0.20+8
    require_selection just 1.54.0
    require_selection apalache 0.58.3

    require_path erlang erl
    require_path elixir elixir
    require_path java java
    require_path just just
    require_path apalache apalache-mc

    otp_release="$(asdf exec erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')"
    [[ "$otp_release" == "27" ]] || fail "Erlang OTP release: expected 27, found $otp_release"

    elixir_output="$(asdf exec elixir --version)"
    grep -Fq "Elixir 1.20.0" <<<"$elixir_output" || fail "unexpected Elixir version output"
    grep -Fq "compiled with Erlang/OTP 27" <<<"$elixir_output" || fail "Elixir was not compiled for OTP 27"

    java_output="$(asdf exec java -XshowSettings:properties -version 2>&1)"
    grep -Fq "17.0.20+8" <<<"$java_output" || fail "unexpected Java build"
    grep -Fq "java.vendor = Eclipse Adoptium" <<<"$java_output" || fail "Java vendor is not Eclipse Adoptium"

    [[ "$(asdf exec just --version)" == "just 1.54.0" ]] || fail "unexpected just version"
    [[ "$(asdf exec apalache-mc version)" == "0.58.3" ]] || fail "unexpected Apalache version"

deps:
    mix deps.get

test:
    MIX_ENV=test mix compile --warnings-as-errors
    mix test

check:
    mix check

docs:
    MIX_ENV=dev mix docs --warnings-as-errors

test-fixed:
    scripts/test_fixed.sh

test-generated:
    scripts/test_generated.sh

test-apalache:
    mix test --include apalache test/victoria/apalache_integration_test.exs
