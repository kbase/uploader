var RetinaConfig = {
    "shock": "https://kbase.us/services/shock-api/",
    "awe": { "url": "http://140.221.85.36:8000",
	     "pipeline": "kb-upload",
	     "project": "data-importer",
	     "clientgroups": "kb_upload"
	   },
    "workspace": "https://kbase.us/services/ws/",
    "authURL": "https://kbase.us/services/authorization/Sessions/Login/",
    "templates": [ "genome", "metagenome", "GWAS_population, ""GWAS_population_trait", "RNASeq_samples", "Variation_samples", "regulatory_network" ],
    "allowedFileEndings": [ "fna", "fas", "fasta", "sff", "fastq", "fq", "txt", "xlsx", "vcf", "vcf.gz" ]
};
