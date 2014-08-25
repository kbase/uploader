var RetinaConfig = {
    "shock": "https://kbase.us/services/shock-api/",
    "awe": { "url": "http://140.221.84.148:8000",
	     "pipeline": "kbase_upload",
	     "project": "data-importer",
	     "clientgroups": "kbase"
	   },
    "workspace": "https://kbase.us/services/ws/",
    "logURL": "http://140.221.67.227/cgi-bin/log.cgi",
    "authURL": "https://kbase.us/services/authorization/Sessions/Login/",
    "templates": [ "genome", "metagenome", "sequence", "GWAS_population","GWAS_population_variations", "GWAS_population_trait", "RNASeq_samples", "Variation_samples", "regulatory_network", "expression_series", "FBA_model", "media", "phenotype_set" ],
    "allowedFileEndings": [ "fna", "fas", "fasta", "faa", "sff", "fastq", "fq", "txt", "xlsx", "vcf", "vcf.gz" ]
};
