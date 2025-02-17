PACKAGE=numbers-parser

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
package_c := $(-,_,$(PACKAGE))

# Change this to the name of a code-signing certificate. A self-signed
# certificate is suitable for this.
IDENTITY=python@figsandfudge.com

# Change this to the location of the proto-dump executable
PROTOC=/usr/local/bin/protoc

# Location of the Numbers application
NUMBERS=/Applications/Numbers.app

# Xcode version of Python that includes LLDB package
LLDB_PYTHON_PATH := ${shell lldb --python-path}

RELEASE_TARBALL=dist/$(PACKAGE)-$(shell python3 setup.py --version).tar.gz

.PHONY: clean veryclean test coverage sdist upload

all:
	@echo "make targets:"
	@echo "    test       - run pytest with all tests"
	@echo "    coverage   - run pytest and generate coverage report"
	@echo "    sdist      - build source distribution"
	@echo "    upload     - upload source package to PyPI"
	@echo "    clean      - delete temporary files for test, coverage, etc."
	@echo "    veryclean  - delete all auto-generated files (requires new bootstrap)"
	@echo "    bootstrap  - rebuild all auto-generated files for new Numbers version"

$(RELEASE_TARBALL): sdist

sdist:
	python3 setup.py sdist

upload: $(RELEASE_TARBALL)
	tox
	twine upload $(RELEASE_TARBALL)

docs:
	python3 setup.py build_sphinx

test:
	PYTHONPATH=src python3 -m pytest tests

coverage:
	PYTHONPATH=src python3 -m pytest --cov=$(package_c) --cov-report=html

BOOTSTRAP_FILES = src/$(package_c)/functionmap.py \
				  src/$(package_c)/generated/__init__.py \
				  src/$(package_c)/mapping.py \

bootstrap: $(BOOTSTRAP_FILES)

.bootstrap/Numbers.unsigned.app:
	@echo $$(tput setaf 2)"Bootstrap: extracting protobuf mapping from Numbers"$$(tput init)
	@mkdir -p .bootstrap
	rm -rf $@
	cp -r $(NUMBERS) $@
	codesign --remove-signature $@/Contents/MacOS/Numbers
	codesign --sign "${IDENTITY}" $@/Contents/MacOS/Numbers

.bootstrap/mapping.json: .bootstrap/Numbers.unsigned.app
	@mkdir -p .bootstrap
	PYTHONPATH=${LLDB_PYTHON_PATH} xcrun python3 src/bootstrap/extract_mapping.py $(NUMBERS)/Contents/MacOS/Numbers $@

.bootstrap/mapping.py: .bootstrap/mapping.json
	@mkdir -p .bootstrap
	python3 src/bootstrap/generate_mapping.py $< $@

src/$(package_c)/functionmap.py: .bootstrap/functionmap.py
	cp $< $@

.bootstrap/functionmap.py:
	@echo $$(tput setaf 2)"Bootstrap: extracting function names from Numbers"$$(tput init)
	@mkdir -p .bootstrap
	python3 src/bootstrap/extract_functions.py $(NUMBERS)/Contents/Frameworks/TSTables.framework/Versions/A/TSTables $@

.bootstrap/protos/TNArchives.proto:
	@echo $$(tput setaf 2)"Bootstrap: extracting protobufs from Numbers"$$(tput init)
	python3 src/bootstrap/protodump.py /Applications/Numbers.app .bootstrap/protos
	python3 src/bootstrap/rename_proto_files.py .bootstrap/protos

src/$(package_c)/mapping.py: .bootstrap/mapping.py
	cp $< $@

src/$(package_c)/generated/TNArchives_pb2.py: .bootstrap/protos/TNArchives.proto
	@echo $$(tput setaf 2)"Bootstrap: compiling Python packages from protobufs"$$(tput init)
	@mkdir -p src/$(package_c)/generated
	for proto in .bootstrap/protos/*.proto; do \
	    $(PROTOC) -I=.bootstrap/protos --proto_path .bootstrap/protos --python_out=src/$(package_c)/generated $$proto; \
	done

src/$(package_c)/generated/__init__.py: src/$(package_c)/generated/TNArchives_pb2.py
	@echo $$(tput setaf 2)"Bootstrap: patching paths in generated protobuf files"$$(tput init)
	python3 src/bootstrap/replace_paths.py src/$(package_c)/generated/T*.py
	touch $@

veryclean:
	make clean
	rm -rf .bootstrap
	rm -rf src/$(package_c)/generated

clean:
	rm -rf src/$(package_c).egg-info
	rm -rf coverage_html_report
	rm -rf dist
	rm -rf build
	rm -rf .tox
	rm -rf .pytest_cache
