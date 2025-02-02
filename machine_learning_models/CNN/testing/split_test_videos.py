import csv
import subprocess
from collections import defaultdict
from pathlib import Path


def split_video(testing_videos_csv: Path, testing_videos_dir: Path):
    """
    Extracts clips listed in the provided csv file.

    :param testing_videos_csv: csv file containing information about the clips to be extracted
    :param testing_videos_dir: directory where the original videos are located
    """
    clips_path = testing_videos_dir / "clips"
    clips_path.mkdir(exist_ok=True)

    with open(testing_videos_csv, "r") as f:
        clips_csv = csv.DictReader(f)

        clips_per_video = defaultdict(list)

        for c in clips_csv:
            clips_per_video[c["filename"]].append(c)

        for video, clips in clips_per_video.items():
            video_file = testing_videos_dir / video
            assert video_file.is_file()

            for clip in clips:
                (clips_path / clip["artworkID"]).mkdir(exist_ok=True)

                # FFmpeg command to extract clips from original videos
                ffmpeg_split_cmd = ["ffmpeg",
                                    "-i", str(video_file),  # input file path
                                    "-c:v copy",  # copy video codec (use same as original video)
                                    "-an",  # remove audio
                                    "-y",  # overwrite output files without asking
                                    "-ss", clip["start"],  # start position of clip
                                    "-t", clip["length"],  # clip length
                                    str(clips_path / clip["artworkID"] / clip["clip_name"])  # output file path
                                    ]

                # call FFmpeg from the command line
                subprocess.call(" ".join(ffmpeg_split_cmd), shell=True)


def process_results(results_csv: Path):
    """
    Processes the resulting csv file produced by the mark_clip_timestamp.py script, by consolidating the start and
    end of each clip into one row; the results are written to a new csv file in the same directory.

    :param results_csv: the csv file created using mark_clip_timestamp.py
    """
    with open(results_csv) as f:
        res = csv.DictReader(f)

        res_sorted = defaultdict(list)

        # sort timestamps according to their corresponding videos, distances, and clip types
        for r in res:
            res_sorted[(r["filename"], r["artworkID"], r["distance"], r["clip_type"], r["vid_length"])].append(
                float(r["timestamp"]))

        # make sure that no more than 2 timestamps are present for each combination
        assert all(len(v) in [1, 2] for v in res_sorted.values())

        clip_type_conversions = {"f": "forward", "d": "downwards", "u": "upwards", "l": "left", "r": "right"}

        processed_csv = []

        for k, v in res_sorted.items():
            filename, artwork_id, distance, clip_type, vid_length = k
            if len(v) == 1:
                # only "f" clips are allowed to have 1 timestamp, the other being the start of the video, 0.0
                assert clip_type == "f"
                v.append(0.0)
                v.sort()

            # make sure no timestamp exceeds the vid_length
            assert max(v) <= int(vid_length)

            start, end = v

            clip_type = clip_type_conversions[clip_type]

            # create name for clip
            clip_name = "_".join([artwork_id, distance, clip_type]) + Path(filename).suffix

            processed_csv.append({"clip_name": clip_name, "filename": filename, "artworkID": artwork_id,
                                  "distance": distance, "clipType": clip_type, "start": start,
                                  "end": end, "length": end - start})

            processed_csv.sort(key=lambda x: x["artworkID"])

        with open(results_csv.parent / "testing_videos.csv", "w") as csv_file:
            header = ["clip_name", "filename", "artworkID", "distance", "clipType", "start", "end", "length"]
            writer = csv.DictWriter(csv_file, fieldnames=header)
            writer.writeheader()
            writer.writerows(processed_csv)


def main():
    # process_results(Path.cwd() / "clip_timestamps.csv")
    split_video(Path.cwd() / "testing_videos.csv", Path("/media/marios/DataUbuntu1/TestingVideos"))


if __name__ == '__main__':
    main()
