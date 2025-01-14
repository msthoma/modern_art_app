import os
import subprocess
import xml.etree.ElementTree as ET
from optparse import OptionParser
from pathlib import Path

import requests


def save_vlc_timestamp(clip_type: str):
    """
    Requests status information from VLC for current video, and saves timestamp information for later splitting of
    the video. This script was used to mark the positions of required clips from the testing videos, which were later
    used to automatically divide them to the desired clips using FFmpeg.

    :param clip_type: the type of the clip the current timestamp refers to; in this case it should refer to Forward,
     Downward, Upward, Left, and Right with the corresponding letters [f, d, u, l, r]
    """
    if clip_type not in "fdulr":
        notify("Clip type provided is not acceptable, should be one of [f, d, u, l, r]")
        raise SystemExit

    # request status from VLC
    r = requests.get("http://127.0.0.1:8080/requests/status.xml", auth=("", "abc"))
    if r.status_code != 200:
        notify(f"Problem requesting information from VLC, status code: {r.status_code}")
        raise SystemExit

    # return status information is in xml form
    root = ET.fromstring(r.text)

    video_name = ""  # filename of current video
    for i in root.find("information"):
        if i.attrib == {"name": "meta"}:
            video_name = i[0].text
            break
    if video_name == "":
        notify("Couldn't get current video filename!")
        raise SystemExit

    percent = root.find("position").text  # current position as a percentage
    vid_length = root.find("length").text  # length of the video in seconds
    timestamp = str(int(vid_length) * float(percent))

    info = [video_name, timestamp, percent, vid_length, get_current("artwork"), get_current("distance"), clip_type]

    # resulting csv will be saved in the same folder as this script
    csv_path = get_script_path() / "clip_timestamps.csv"
    if not csv_path.is_file():
        # create csv file and print header
        with open(csv_path, "a") as f:
            f.write("filename,timestamp,percent,vid_length,artworkID,distance,clip_type\n")

    with open(csv_path, "a") as f:
        f.write(",".join(info) + "\n")

    notify(f"Saved {round(float(timestamp), 2)} timestamp for {clip_type}-{video_name}")


def get_script_path():
    """
    :return: the path that this script is currently located
    """
    return Path(os.path.realpath(__file__)).parent


def change_current(option: str):
    """
    Can be used to set the current artwork and distance, this works by simply appending characters in a txt file and
    counting their number to determine the current artwork and distance.

    :param option: should be either "distance" or "artwork"
    """
    if option not in ["distance", "artwork"]:
        raise SystemExit

    f_name = get_script_path() / f"{option}.txt"

    # if the file does not exist, creating it seems not to work?
    with open(f_name, "a+") as f:
        # increment file by one character, does not matter which; this series of characters' length is calculated,
        # and based on it the current distance/artwork is set
        f.write("0")
    notify(f"Current {option}: {get_current(option)}")


def get_current(option: str):
    """
    Can be used to get the current artwork and distance for two correspoding text files, these must be already
    present, and can be created by using change_current().

    :param option: should be either "distance" or "artwork"
    :return: the current artwork or distance as requested
    """
    distances = ["1m", "1.5m", "2.5m"]
    artworkIDs = ["2-3_sfikas", "armament_phinikarides", "ascent_ladommatos", "autumn_chrysochos", "crucified_savvides",
                  "game_of_shapes_chrysochos", "ground_plan_hadjida", "no_artwork", "presence_votsis",
                  "secession_bargilly", "the_cyclist_votsis", "the_great_greek_encyclopaedia_makrides",
                  "the_observer_kyriakou", "throne_ii_chrysochos", "untitled_hadjida", "untitled_kouroussis",
                  "untitled_votsis"]

    f_name = get_script_path() / f"{option}.txt"

    with open(f_name, "r") as f:
        current = f.read()
        if option == "distance":
            return distances[len(current) % len(distances)]
        elif option == "artwork":
            return artworkIDs[len(current) % len(artworkIDs)]


def notify(msg: str):
    """
    Shows a simple text notification in Ubuntu.

    :param msg: the message to be shown in the notification
    """
    subprocess.Popen(['notify-send', msg])


def main():
    """
    The videos that were used to test the CNN models and the recognition algorithms were taken in the form: 10s
    forward, 5s downwards, 5s upwards, 5s left, 5s right (this order was sometimes slightly different), 3 times for
    each artwork at 3 distances, 1m, 1.5m, and 2.5m; and so this script was used to automate the marking of the exact
    boundaries of these clips in each video, so they could be programmatically be cut using FFmpeg.

    The script is meant to be used from the command line while the video is playing in VLC, and accepts an argument
    -t like so:

    `python3 path/to/script/split_testing_videos.py -t f`

    The argument accepts any of ["f", "d", "u", "l", "r", "artwork", "distance"], with the letters corresponding to
    the 5 directions, forward, downwards... etc. When the command is executed as shown above, it would mark the
    current position of the currently playing video as "forward"; two such marks should be made for the start and end
    of each direction (though if "forward" starts at 0:00 it can be skipped).

    Before any marks are made, the "distance" and "artwork" variables should be set by calling the command with the
    those two strings (not both at once!) - this simply iterates through all possible values until the desired value is
    reached (they can also be manually set by editing their corresponding files, see the change_current() function
    for explanations).

    To make the process fast, the execution of the script can be bound to a few keyboard shortcuts, so the script can
    be called while watching the video. For example, in Linux (Ubuntu), I used the following shortcuts (they can be
    set by going to Settings->Keyboard Shortcuts):

    - Shift+Ctrl+F: `python3 path/to/script/mark_clip_timestamp.py -t f`
    - Shift+Ctrl+D: `python3 path/to/script/mark_clip_timestamp.py -t d`
    - etc.

    The results are saved in a .csv file in the same folder as the script.

    The script makes use of the VLC HTTP requests feature, which had to be enabled in the program's settings,
    see these links for details:

    - https://wiki.videolan.org/VLC_HTTP_requests/
    - https://wiki.videolan.org/Documentation:Modules/http_intf/

    The notification functionality is specific to Ubuntu, so it should be replaced or adjusted to work in other OSs,
    see this link for more information/alternatives: https://askubuntu.com/questions/108764/how-do-i-send-text-messages-to-the-notification-bubbles

    Make sure to quit VLC after every video (Ctrl+Q works), since otherwise VLC seems to report values from the
    previous video if its not exited properly.
    """
    parser = OptionParser()
    parser.add_option("-t",
                      dest="type",
                      help="Type of video clip the timestamp to be saved refers to; if artwork or distance is "
                           "specified, the corresponding variable is incremented.",
                      type="choice",
                      action="store",
                      choices=["f", "d", "u", "l", "r", "artwork", "distance"],
                      default="f"
                      )

    options, args = parser.parse_args()

    if options.type in "fdulr":
        save_vlc_timestamp(options.type)
    elif options.type in ["artwork", "distance"]:
        change_current(options.type)


if __name__ == '__main__':
    main()
