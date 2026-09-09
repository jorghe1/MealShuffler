#!/usr/bin/env python3
"""Argument labels at a call site, against the function it calls.

Renaming a parameter is a two-part edit, and the second part is easy to miss: two calls to
`candidatePool` kept passing `context:` after the parameter became `dayContext:`, which reads
fine, passes every other check here, and fails on a build machine ten minutes later with
"Extra argument 'context' in call". This is the cheapest possible stand-in for a compiler.

Deliberately narrow, because a wrong answer here costs more than a missed one:

  * only functions declared `private`/`fileprivate` in the file being read, so the declaration
    really is the only one a call in that file could mean;
  * only calls written bare, never `something.name(...)`, which could be any type's method;
  * a call with a trailing closure is allowed to leave its last parameter unwritten;
  * anything the parser is unsure of is skipped rather than guessed at.

It checks order, not just spelling: `context:` is a real label on `candidatePool`, just not in
fifth place, so comparing sets would have found nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DECLARATION = re.compile(r'\b(?:private|fileprivate)\s+(?:static\s+)?func\s+(\w+)\s*\(')
CALL = re.compile(r'(?<![\w.$])(\w+)\s*\(')
ARGUMENT_LABEL = re.compile(r'^\s*(\w+)\s*:')
# A parameter is `label name: Type`, `name: Type`, or `_ name: Type`, optionally `= default`.
PARAMETER = re.compile(r'^\s*(?:(\w+|_)\s+)?(\w+)\s*:')

SKIP = {'if', 'for', 'while', 'switch', 'guard', 'return', 'catch', 'init', 'func'}


def blank_literals(source: str) -> str:
    """Replace comments and string bodies with spaces, keeping every offset intact.

    Parentheses and colons inside a string or a comment are not syntax, and treating them as
    syntax is the fastest way to make a checker like this untrustworthy. A blanked string
    leaves one `0` where it opened, so `fold("egg")` still reads as a call with one argument
    rather than as a call with none.
    """
    out = list(source)
    index, length = 0, len(source)
    while index < length:
        two = source[index:index + 2]
        if two == '//':
            end = source.find('\n', index)
            end = length if end == -1 else end
            for position in range(index, end):
                out[position] = ' '
            index = end
        elif two == '/*':
            depth, position = 1, index + 2
            while position < length and depth:
                if source[position:position + 2] == '/*':
                    depth, position = depth + 1, position + 2
                elif source[position:position + 2] == '*/':
                    depth, position = depth - 1, position + 2
                else:
                    position += 1
            for blank in range(index, min(position, length)):
                if out[blank] != '\n':
                    out[blank] = ' '
            index = position
        elif source[index:index + 3] == '"""':
            end = source.find('"""', index + 3)
            end = length if end == -1 else end + 3
            for blank in range(index, end):
                if out[blank] != '\n':
                    out[blank] = ' '
            out[index] = '0'
            index = end
        elif source[index] == '"':
            position = index + 1
            while position < length and source[position] != '"':
                # An interpolation can hold anything, including quotes; step over it whole.
                if source[position:position + 2] == '\\(':
                    depth, position = 1, position + 2
                    while position < length and depth:
                        depth += (source[position] == '(') - (source[position] == ')')
                        position += 1
                    continue
                position += 2 if source[position] == '\\' else 1
            position = min(position + 1, length)
            for blank in range(index, position):
                if out[blank] != '\n':
                    out[blank] = ' '
            out[index] = '0'
            index = position
        else:
            index += 1
    return ''.join(out)


def close_paren(source: str, open_index: int):
    """Index of the `)` matching the `(` at `open_index`, or None if it never closes."""
    depth, index, length = 0, open_index, len(source)
    while index < length:
        character = source[index]
        if character in '([{':
            depth += 1
        elif character in ')]}':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def split_arguments(body: str):
    """Top-level comma-separated pieces, ignoring commas nested inside anything."""
    pieces, depth, start = [], 0, 0
    for index, character in enumerate(body):
        if character in '([{':
            depth += 1
        elif character in ')]}':
            depth -= 1
        elif character == ',' and depth == 0:
            pieces.append(body[start:index])
            start = index + 1
    tail = body[start:]
    if tail.strip() or pieces:
        pieces.append(tail)
    return [piece for piece in pieces if piece.strip()]


def parameters(body: str):
    """(external label or None, has a default) for each declared parameter."""
    declared = []
    for piece in split_arguments(body):
        match = PARAMETER.match(piece)
        if match is None:
            return None
        label = match.group(1) if match.group(1) else match.group(2)
        declared.append((None if label == '_' else label, '=' in piece.split(':', 1)[1]))
    return declared


def call_labels(body: str):
    return [
        match.group(1) if (match := ARGUMENT_LABEL.match(piece)) else None
        for piece in split_arguments(body)
    ]


def mismatch(declared, supplied, trailing_closure: bool):
    """The first reason this call cannot be the declaration, or None if it can."""
    position = 0
    for label in supplied:
        while position < len(declared) and declared[position][0] != label:
            if not declared[position][1]:
                missing = declared[position][0] or '_'
                if label is None:
                    return "argument %d has no label, but '%s:' is expected" % (position + 1, missing)
                return "'%s:' where '%s:' is expected" % (label, missing)
            position += 1
        if position == len(declared):
            return "no parameter '%s:' left to match" % (label if label else '_')
        position += 1
    remaining = [name or '_' for name, default in declared[position:] if not default]
    if trailing_closure and remaining:
        remaining = remaining[:-1]
    if remaining:
        return 'nothing passed for ' + ', '.join("'%s:'" % name for name in remaining)
    return None


def check(path: pathlib.Path):
    source = path.read_text(encoding='utf-8')
    stripped = blank_literals(source)

    declarations, declaration_spans = {}, []
    for match in DECLARATION.finditer(stripped):
        end = close_paren(stripped, match.end() - 1)
        if end is None:
            continue
        declaration_spans.append((match.start(), end))
        declared = parameters(stripped[match.end():end])
        if declared is None:
            continue
        # An overloaded name means a call could legitimately match either; leave it alone.
        declarations[match.group(1)] = None if match.group(1) in declarations else declared

    problems = []
    for match in CALL.finditer(stripped):
        name = match.group(1)
        if name in SKIP or name not in declarations or declarations[name] is None:
            continue
        if any(start <= match.start() <= end for start, end in declaration_spans):
            continue
        end = close_paren(stripped, match.end() - 1)
        if end is None:
            continue
        trailing = bool(re.match(r'\s*\{', stripped[end + 1:end + 3]))
        reason = mismatch(declarations[name], call_labels(stripped[match.end():end]), trailing)
        if reason:
            line = source.count('\n', 0, match.start()) + 1
            problems.append('%s:%d: %s(...) — %s' % (path.relative_to(ROOT), line, name, reason))
    return problems


def main():
    files = sorted(
        path for directory in ('MealShuffler', 'MealShufflerTests', 'MealShufflerWidget',
                               'MealShufflerShare')
        for path in (ROOT / directory).rglob('*.swift')
    )
    problems = [problem for path in files for problem in check(path)]
    print('checked %d Swift files for argument-label drift' % len(files))
    if problems:
        for problem in problems:
            print('  ' + problem)
        print('%d call(s) do not match the function they call' % len(problems))
        return 1
    print('every call matches the function it calls')
    return 0


if __name__ == '__main__':
    sys.exit(main())
