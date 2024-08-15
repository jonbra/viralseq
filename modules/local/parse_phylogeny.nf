process PARSE_PHYLOGENY {
    tag "$meta.id"
    label 'process_single'

    conda "YOUR-TOOL-HERE"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/YOUR-TOOL-HERE':
        'docker.io/pegi3s/biopython:1.78' }"

    input:
    tuple val(meta) , path(treefile)
    //tuple val(meta) , path(gff_extract_fasta), path(treefile)
    //tuple val(meta2), path(references)

    output:
    tuple val(meta), path("*parse_phylo*.csv")    , emit: parse_phylo
    //tuple val(meta), path("*temp_prefix_header*.csv")   , emit: header
    //tuple val(meta), path("*.fasta"), emit: percentcalc_fasta
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def gene_name = "${meta.gene}"
    """
    # Parse the phylogeny (treefile), identify the clade identity for each of the de novo contigs,
    # and identify the nearest reference sequences.
    # Output this as a csv file
    parse_phylo.py $prefix $treefile $gene_name

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Python: \$(python --version 2>&1 | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // TODO nf-core: A stub section should mimic the execution of the original module as best as possible
    //               Have a look at the following examples:
    //               Simple example: https://github.com/nf-core/modules/blob/818474a292b4860ae8ff88e149fbcda68814114d/modules/nf-core/bcftools/annotate/main.nf#L47-L63
    //               Complex example: https://github.com/nf-core/modules/blob/818474a292b4860ae8ff88e149fbcda68814114d/modules/nf-core/bedtools/split/main.nf#L38-L54
    """
    touch ${prefix}.bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        : \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' ))
    END_VERSIONS
    """


}
