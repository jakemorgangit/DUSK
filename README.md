# DUSK (Disk Usage SKanner)

### Overview

DUSK is an interactive disk usage scanning and navigation tool written in Perl. It builds a one-time cached map of disk usage using a recursive `du` scan and lets you interactively navigate the directory tree via a terminal-based menu. Each file and directory is listed along with a human-readable size, a bar graph showing its relative disk usage compared to others, and a type indicator ("D" for directory, "F" for file). When a file is selected, an info box displays additional details such as owner, permissions, timestamps, and the output from the external `file` command.

### Motivation

This project was developed as a response to a client's decision not to install `ncdu` – a popular disk usage analyzer. Despite `ncdu`'s powerful features, the client did not see any added benefit in installing a separate tool. DUSK was created to provide a similar interactive interface using only default tools available on Linux, allowing for disk usage analysis without external dependencies.

### Features

#### One-Time Scan and Caching

DUSK performs a one-time recursive scan using `du -a -b` to cache the entire file and directory tree in memory. This avoids repeated scanning during navigation.

#### Interactive Terminal Menu

Navigate through directories and files using arrow keys and enter your selection. A scrolling viewport ensures that the selected item is always visible.

![image](https://github.com/user-attachments/assets/46b99403-d2ee-4363-92fa-561589652d25)


#### Visual Representation

Each item is displayed with:

- A human-readable size (e.g., `27.0GB`)
- A bar graph representing its size relative to the largest item in the current directory
- A type column indicating whether the item is a directory (`D`) or a file (`F`)

#### File Information Infobox

When a file is selected, an info box appears displaying additional details such as owner, group, permissions, modification/creation timestamps, and the output from the `file` command.

![image](https://github.com/user-attachments/assets/71b15c38-4dd4-4614-b0a3-86abf353e3ce)

#### Scanning Progress Indicator

If a directory has many entries, a simulated progress message appears while the list is being generated, providing visual feedback that the scan is in progress.

## Usage

### Running DUSK

#### Default:
Scan from the root directory (`/`):

```sh
./dusk.pl
```

If scanning on a CPU starved host, try running this to ensure other processes are not in contention:

```
 nice -n 10 taskset -c 0 perl dusk.pl
```

#### Current Working Directory:
Start scanning from the current directory:

```sh
./dusk.pl --pwd
```

#### Specific Directory:
Start scanning from a specified directory (use absolute paths for best performance):

```sh
./dusk.pl --path '/absolute/path/to/directory'
```

![image](https://github.com/user-attachments/assets/117b0a4e-c597-499b-b132-3d71c9cefa5e)


### Navigation

#### Arrow Keys:
- Use the up and down arrow keys to move through the list.
- The selection does not wrap around—navigation stops at the top and bottom of the menu.

#### Enter:
- Selecting a directory navigates into that directory.
- Selecting a file displays a file information infobox.
- Use "Go up one level" to move back up in the directory tree.

#### Quit:
- Press `q` at any time to exit DUSK.

## Cautions & Recommendations

### Resource Intensive

Since DUSK builds a complete disk map in memory during its one-time scan, it can be resource intensive, especially on systems with large file systems. It is recommended to use this tool with caution and on systems where you are aware of the disk usage.

### Absolute Paths

For better performance and to avoid scanning an unnecessarily large directory tree (like `/`), it is advisable to run DUSK on specific, absolute paths rather than the entire root.

## Dependencies

DUSK relies on the following standard Perl modules:

- `Term::ReadKey` – For capturing interactive key presses and terminal size.
- `Getopt::Long` – For command-line option parsing.
- `Storable` – For caching the disk usage tree.
- `POSIX` – For formatting timestamps.

These modules are included by default in most Perl installations.

## License

This project is provided "as is" without warranty of any kind. Use at your own risk.
