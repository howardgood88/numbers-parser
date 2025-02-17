# numbers-parser

[![build:](https://github.com/masaccio/numbers-parser/actions/workflows/run-all-tests.yml/badge.svg)](https://github.com/masaccio/numbers-parser/actions/workflows/run-all-tests.yml)
[![build:](https://github.com/masaccio/numbers-parser/actions/workflows/codeql.yml/badge.svg)](https://github.com/masaccio/numbers-parser/actions/workflows/codeql.yml)

`numbers-parser` is a Python module for parsing [Apple Numbers](https://www.apple.com/numbers/)
`.numbers` files. It supports Numbers files generated by Numbers version 10.3, and up with the latest tested version being 12.1
(current as of June 2022).

It supports and is tested against Python versions from 3.8 onwards. It is not compatible with earlier versions of Python.

Currently supported features of Numbers files are:

* Multiple sheets per document
* Multiple tables per sheet
* Text, numeric, date, currency, duration, percentage cell types

Formulas rely on Numbers storing current values which should usually be
the case. Formulas themselves rather than the computed values can optionally
be extracted. Styles are not supported.

As of version 3.0, `numbers-parser` has limited support for creating Numbers files.

## Installation

``` bash
python3 -m pip install numbers-parser
```

A pre-requisite for this package is [python-snappy](https://pypi.org/project/python-snappy/) which will be installed by Python automatically, but python-snappy also requires that the binary libraries for snappy compression are present. The most straightforward way to achieve this is to use [Homebrew](https://brew.sh) and source Python from Homebrew rather than from macOS:

``` bash
brew install snappy python3
python3 -m pip install numbers-parser
```

On Apple Silicon, the default installation of the protobuf package that is installed by PIP is pure-python rather than native code. Processing speed of Numbers spreadsheets can be greatly improved by installing C++ support as described in thie README in [Protobuf updates](#protobuf-updates)

## Usage

Reading documents:

``` python
from numbers_parser import Document
doc = Document("my-spreasdsheet.numbers")
sheets = doc.sheets
tables = sheets[0].tables
rows = tables[0].rows()
```

### Referring to sheets and tables

Both sheets and names can be accessed from lists of these objects using an integer index (`list` syntax) and using the name
of the sheet/table (`dict` syntax):

``` python
# list access method
sheet_1 = doc.sheets[0]
print("Opened sheet", sheet_1.name)

# dict access method
table_1 = sheets["Table 1"]
print("Opened table", table_1.name)
```

As of version 3.0, the `Document.sheets()` and `Sheet.tables()` methods are deprecated and will issue a `DeprecationWarning` if used. Instead of these functions, you should use the properties as demonstrated above. The legacy methods will be removed in a future version of `numbers-parser`.

### Accessing data

`Table` objects have a `rows` method which contains a nested list with an entry for each row of the table. Each row is
itself a list of the column values. Empty cells in Numbers are returned as `None` values.

``` python
data = sheets["Table 1"].rows()
print("Cell A1 contains", data[0][0])
print("Cell C2 contains", data[2][1])
```

### Cell references

In addition to extracting all data at once, individual cells can be referred to as methods

``` python
doc = Document("my-spreasdsheet.numbers")
sheets = doc.sheets
tables = sheets["Sheet 1"].tables
table = tables["Table 1"]

# row, column syntax
print("Cell A1 contains", table.cell(0, 0))
# Excel/Numbers-style cell references
print("Cell C2 contains", table.cell("C2"))
```

### Merged cells

When extracting data using ```data()``` merged cells are ignored since only text values
are returned. The ```cell()``` method of ```Table``` objects returns a ```Cell``` type
object which is typed by the type of cell in the Numbers table. ```MergeCell``` objects
indicates cells removed in a merge.

``` python
doc = Document("my-spreasdsheet.numbers")
sheets = doc.sheets
tables = sheets["Sheet 1"].tables
table = tables["Table 1"]

cell = table.cell("A1")
print(cell.merge_range)
print(f"Cell A1 merge size is {cell.size[0]},{cell.size[1]})
```

### Row and column iterators

Tables have iterators for row-wise and column-wise iteration with each iterator
returning a list of the cells in that row or column

``` python
for row in table.iter_rows(min_row=2, max_row=7, values_only=True):
    sum += row
for col in table.iter_cols(min_row=2, max_row=7):
    sum += col.value
```

### Pandas

Since the return value of `data()` is a list of lists, you can pass this directly to pandas. Assuming you have a Numbers table with a single header which contains the names of the pandas series you want to create you can construct a pandas dataframe using:

``` python
import pandas as pd

doc = Document("simple.numbers")
sheets = doc.sheets
tables = sheets[0].tables
data = tables[0].rows(values_only=True)
df = pd.DataFrame(data[1:], columns=data[0])
```

### Bullets and lists

Cells that contain bulleted or numbered lists can be identified by the `is_bulleted` property. Data from such cells is returned using the `value` property as with other cells, but can additionally extracted using the `bullets` property. `bullets` returns a list of the paragraphs in the cell without the bullet or numbering character. Newlines are not included when bullet lists are extracted using `bullets`.

``` python
doc = Document("bullets.numbers")
sheets = doc.sheets
tables = sheets[0].tables
table = tables[0]
if not table.cell(0, 1).is_bulleted:
    print(table.cell(0, 1).value)
else:
    bullets = ["* " + s for s in table.cell(0, 1).bullets]
    print("\n".join(bullets))
```

Bulleted and numbered data can also be extracted with the bullet or number characters present in the text for each line in the cell in the same way as above but using the `formatted_bullets` property. A single space is inserted between the bullet character and the text string and in the case of bullets, this will be the Unicode character seen in Numbers, for example `"• some text"`.

## Writing Numbers files

*This is considered experimental* and has a number of limitations. You are highly recommened not to overwrite working Numbers files and instead save data to a new file.

### Limitations

Currently only documents with single table in single sheet are supported. Most cell formats should work with the expception of `MergedCell` and `BulletedTextCell`. The following features may be introduced in the future:

* bullets in text cells (`BulletedTextCell`)
* multiple tables per sheet
* multiple sheets for spreadsheet document

During the same process, cell widths are reset and cell formats are removed from the saved file.

### Editing cells

`numbers-parser` will automatically empty rows and columns for any cell references that out of range of the current table. The `write` method accepts the same cell numbering notation as `cell` plus an additional argument representing the new cell value. The type of the new value will be used to determine the cell type.

``` python
doc = Document("my-spreadsheet.numbers")
sheets = doc.sheets
tables = sheets[0].tables
table = tables[0]
table.write(1, 1, "This is new text")
table.write("B7", datetime(2020, 12, 25))
doc.save("my-edited-spreadsheet.numbers")
```

Sheet names and table names can be changed by assigning a new value to the `name` of each:

```python
sheets[0].name = "My new sheet"
tables[0].name = "Edited table"
````

## Numbers File Formats

Numbers uses a proprietary, compressed binary format to store its tables.
This format is comprised of a zip file containing images, as well as
[Snappy](https://github.com/google/snappy)-compressed
[Protobuf](https://github.com/protocolbuffers/protobuf) `.iwa` files containing
metadata, text, and all other definitions used in the spreadsheet.

### Protobuf updates

As `numbers-parser` includes private Protobuf definitions extracted from a copy of Numbers, new versions of Numbers will inevitably create `.numbers` files that cannot be read by `numbers-parser`. As new versions of Numbers are released, running `make bootstrap` will perform all the steps necessary to recreate the protobuf files used `numbers-parser` to read Numbers spreadsheets.

On Apple Silicon Macs, the default protobuf package installation does not include the C++ optimised version which is required by the bootstrapping scripts to extract protobufs. You will receive the following error during build if this is the case:

 `This script requires the Protobuf installation to use the C++ implementation. Please reinstall Protobuf with C++ support.`

 To include the C++ support, download a released version of Google protobuf [from github](https://github.com/protocolbuffers/protobuf). Build instructions are in the [`src/README.md`](https://github.com/protocolbuffers/protobuf/blob/main/src/README.md) in the distribution but for macOS with [Homebrew](https://brew.sh) the two steps are, firstly to install the native protobuf libraries, which must be on your `LD_LIBRARY_PATH`:

``` bash
brew install autoconf automake libtool
./autogen.sh
./configure --prefix=/usr/local
make check -j`sysctl -n hw.ncpu`
sudo make install
```

And then to install the Python libraries with C++ support. If you already have protobuf install via Homebrew, you will need to `brew unlink` the installation.

``` bash
cd python
python3 setup.py build --cpp_implementation
python3 setup.py test --cpp_implementation
python3 setup.py install --cpp_implementation
```
  
  This will install protobuf in a folder above the source installation which can then be used by `make bootstrap` in the `numbers-parser` source tree.

## Credits

`numbers-parser` was built by [Jon Connell](http://github.com/masaccio) but relies heavily on from [prior work](https://github.com/psobot/keynote-parser) by [Peter Sobot](https://petersobot.com) to read the IWA format archives used by Apple's iWork family of applications, and to regenerate the mapping files required for Python. Both modules are derived from [previous work](https://github.com/obriensp/iWorkFileFormat/blob/master/Docs/index.md) by [Sean Patrick O'Brien](http://www.obriensp.com).

Decoding the data structures inside Numbers files was helped greatly by [Stingray-Reader](https://github.com/slott56/Stingray-Reader) by [Steven Lott](https://github.com/slott56).

Formula tests were adapted from JavaScript tests used in
[fast-formula-parser](https://github.com/LesterLyu/fast-formula-parser).

Decimal128 conversion to and from byte storage was adapted from work done by the
[SheetsJS project](https://github.com/SheetJS/sheetjs). SheetJS also helped greatly with some of the steps required to successfully save a Numbers spreadsheet.

## License

All code in this repository is licensed under the [MIT License](https://github.com/masaccio/numbers-parser/blob/master/LICENSE.rst)
