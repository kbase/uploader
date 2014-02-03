TOP_DIR = ../..
TOOLS_DIR = $(TOP_DIR)/tools
DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment
-include $(TOOLS_DIR)/Makefile.common

PERL_PATH = $(DEPLOY_RUNTIME)/bin/perl
SERVICE_NAME = uploader
SERVICE_DIR  = $(TARGET)/services/$(SERVICE_NAME)
TPAGE_CGI_ARGS = --define perl_path=$(PERL_PATH) --define perl_lib=$(SERVICE_DIR)/api

# TPAGE_LIB_ARGS = --define target=$(TARGET) \
# --define m5nr_name=$(SERVICE_NAME) \
# --define m5nr_solr=$(SOLR_URL)/solr \
# --define m5nr_fasta=$(SERVICE_STORE)/md5nr \
# --define api_dir=$(SERVICE_DIR)/api
# TPAGE_SOLR_ARGS = --define host_port=$(SOLR_PORT) --define data_dir=$(SERVICE_DATA) --define max_bool=100000
TPAGE := $(shell which tpage)

# to run local solr in kbase env
# 	make deploy-dev
# to run outside of kbase env
# 	make standalone-m5nr PERL_PATH=<perl bin> SERVICE_STORE=<dir for large data> DEPLOY_RUNTIME=<dir to place solr> M5NR_VERSION=<m5nr version #> SERVICE_DIR=<location of service>
# to just install and load solr
# 	make standalone-solr SERVICE_STORE=<dir to place solr data> DEPLOY_RUNTIME=<dir to place solr> M5NR_VERSION=<m5nr version #>

### Default make target
default: build-ui

### Test Section
TESTS = $(wildcard test/scripts/test_*.t)

test: test-ui

test-ui:
	@echo "testing service (solr API) ..."

all: deploy

clean:

uninstall: clean
	-rm -rf $(SERVICE_STORE)
	-rm -rf $(SERVICE_DIR)

deploy: deploy-ui
	@echo "Deploying UI"

deploy-ui: build-ui

build-ui:
	mkdir -p $(SERVICE_DIR)/webroot
#	cp *.html $(SERVICE_DIR)/webroot/
#	cp -R validator/* $(SERVICE_DIR)/webroot/
	cp -R * $(SERVICE_DIR)/webroot/

deploy-client: 
	@echo "no client"



deploy-docs: build-docs

### all targets below are not part of standard make && make deploy

deploy-dev:
	@echo "no dev deployment"



-include $(TOOLS_DIR)/Makefile.common.rules
