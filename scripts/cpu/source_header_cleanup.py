"""Deterministic comment-only transforms for explicitly reviewed source imports."""
import hashlib
import re


NOTICE_LINE = re.compile(rb'\bCopyright\b|SPDX-License-Identifier|\bLICENSE\b|\bLicensed\b', re.I)
LINE_HEADER = re.compile(rb'(?://[^\r\n]*(?:\r\n|\n|\r))+')
MODULE_HEADER = re.compile(
    rb'(^endmodule[ \t]*(?:\r\n|\n|\r)[ \t\r\n]*)'
    rb'((?://[^\r\n]*(?:\r\n|\n|\r))+)(?=module[ \t])', re.M)
MODULE_HEADER_V2 = re.compile(
    rb'(^endmodule[ \t]*(?:\r\n|\n|\r)[ \t\r\n]*)'
    rb'((?:(?://[^\r\n]*(?:\r\n|\n|\r))|(?:[ \t]*(?:\r\n|\n|\r)))+)'
    rb'(?=module[ \t])', re.M)
APACHE_MODULE_NOTICE = re.compile(
    rb'^//-+\r?\n//[ \t]+biRISC-V CPU\r?\n'
    rb'(?://[^\r\n]*\r?\n)*?// limitations under the License\.\r?\n//-+\r?\n', re.M)


def clean_leading_header(data):
    """Preserve all bytes outside the leading notice, including source encoding."""
    match = LINE_HEADER.match(data)
    if match:
        header = match.group()
        if (header.startswith(b'//---') and b'Copyright' in header
                and b'Licensed under the Apache License' in header):
            return data[match.end():]
        kept = b''.join(line for line in header.splitlines(keepends=True)
                        if not NOTICE_LINE.search(line))
        return kept + data[match.end():]
    if data.startswith(b'/*'):
        end = data.find(b'*/')
        if end < 0:
            raise ValueError('unterminated leading comment')
        header = data[:end + 2]
        kept = []
        for line in header.splitlines(keepends=True):
            if NOTICE_LINE.search(line):
                # Never remove delimiters or any source following the comment.
                if b'/*' in line or b'*/' in line:
                    raise ValueError('notice shares comment delimiter; explicit review required')
            else:
                kept.append(line)
        return b''.join(kept) + data[end + 2:]
    return data


def clean_header(data):
    data = clean_leading_header(data)
    # A file can contain several modules. Only a notice between an endmodule
    # boundary and the next module declaration is another module header.
    def module_notice(match):
        kept = b''.join(line for line in match.group(2).splitlines(keepends=True)
                        if not NOTICE_LINE.search(line))
        return match.group(1) + kept
    return MODULE_HEADER.sub(module_notice, data)


def replay_cleanup(data, record, output_sha256):
    if (not isinstance(record, dict) or set(record) != {'algorithm', 'source_sha256'}
            or record['algorithm'] not in ('leading-notice-v1', 'module-notice-v2')
            or not re.fullmatch(r'[0-9a-f]{64}', record['source_sha256'])):
        raise ValueError('invalid header cleanup record')
    actual = hashlib.sha256(data).hexdigest()
    if actual == output_sha256:
        return data  # A reviewed working tree can already contain the exact output.
    if actual != record['source_sha256']:
        raise ValueError('cleanup base hash mismatch')
    cleaned = clean_module_headers(data) if record['algorithm'] == 'module-notice-v2' else clean_header(data)
    if cleaned == data:
        raise ValueError('no supported leading notice')
    return cleaned  # The importer still requires the exact admitted output hash.


def clean_module_headers(data):
    """V2 also handles blank lines inside inter-module comment headers.

    V1 stays byte-for-byte reproducible for previously admitted files.
    Only comments between a complete endmodule and the next module are read.
    """
    def module_notice(match):
        header = APACHE_MODULE_NOTICE.sub(b'', match.group(2))
        kept = b''.join(line for line in header.splitlines(keepends=True)
                        if not NOTICE_LINE.search(line))
        return match.group(1) + kept
    return MODULE_HEADER_V2.sub(module_notice, clean_leading_header(data))
