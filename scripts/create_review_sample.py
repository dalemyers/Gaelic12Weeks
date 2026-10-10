"""Create a redistributable review ZIP from the repository's original test tone."""

import argparse
from pathlib import Path
import zipfile


def titled_audio(source: bytes, title: str) -> bytes:
    """Replace an optional ID3 tag with an ASCII title the importer can read.

    :param source: Original MP3 bytes.
    :param title: ASCII sample description.
    :returns: MP3 bytes with an ID3v2.3 TIT2 frame.
    """
    if source[:3] == b"ID3":
        if len(source) < 10 or any(byte & 0x80 for byte in source[6:10]):
            raise ValueError("The source has an invalid ID3 header.")
        size = sum(byte << shift for byte, shift in zip(source[6:10], (21, 14, 7, 0)))
        end = 10 + size + (10 if source[3] == 4 and source[5] & 0x10 else 0)
        if end >= len(source):
            raise ValueError("The source has no audio after its ID3 tag.")
        source = source[end:]
    payload = b"\x00" + title.encode("ascii")
    frame = b"TIT2" + len(payload).to_bytes(4, "big") + b"\x00\x00" + payload
    size = bytes((len(frame) >> shift) & 0x7F for shift in (21, 14, 7, 0))
    return b"ID3\x03\x00\x00" + size + frame + source


def create_sample(destination: Path) -> None:
    """Write original tones for a complete lesson and two bonus groups.

    :param destination: New ZIP path; existing files are never overwritten.
    """
    root = Path(__file__).resolve().parents[1]
    source = (root / "IntroEditorTests/Fixtures/synthetic.mp3").read_bytes()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for track_id in [*range(2, 15), 145, 148]:
            audio = titled_audio(source, f"Original review tone - track {track_id}")
            archive.writestr(f"Sample/1_{track_id:03d}.mp3", audio)
        archive.writestr("LICENSE.txt", (root / "LICENSE").read_bytes())
        archive.writestr(
            "README.txt",
            "Original quiet 440 Hz tones, not book audio or language lessons.\n"
            "The app uses its normal lesson labels for these sample track IDs.\n"
            "Each recording lasts about four seconds. Source tone and code are MIT licensed.\n"
            "Use only in a fresh test installation: importing replaces its current audio library.\n",
        )


def main() -> None:
    """Parse the output path and create the review archive."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output", nargs="?", type=Path, default=Path("build/ReviewSample.zip")
    )
    args = parser.parse_args()
    create_sample(args.output)
    print(f"Created {args.output}")


if __name__ == "__main__":
    main()
