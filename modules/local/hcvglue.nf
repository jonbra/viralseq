process HCVGLUE {
    
    label 'process_low'

    // conda "YOUR-TOOL-HERE"
    // container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
    //     'https://depot.galaxyproject.org/singularity/YOUR-TOOL-HERE':
    //     'docker.io/docker:24.0.7-cli-alpine3.18' }"

    stageInMode = 'copy' // Can't mount symlinked files into docker containers

    input:
    path '*'

    output:
    path("*.json"), optional: true, emit: GLUE_json
    path "versions.yml"                            , emit: versions

    script:
    """
    # Copy bam files from bams/ directory so they are not present in work directory as links.
    # This is for mounting to the docker image later
    #cp bams/*.bam .
    
    # Pull the latest images
    docker pull cvrbioinformatics/gluetools-mysql:latest
    docker pull cvrbioinformatics/gluetools:latest

    # Start the gluetools-mysql containter
    # Remove the container in case it is already running
    #docker stop gluetools-mysql
    #docker rm gluetools-mysql
    #docker run --detach --name gluetools-mysql cvrbioinformatics/gluetools-mysql:latest

    # Install the pre-built GLUE HCV project
    docker start gluetools-mysql
    docker exec gluetools-mysql installGlueProject.sh ncbi_hcv_glue

    # Make a for loop over all bam files and run HCV-GLUE
    ## Adding || true to the end of the command to prevent the pipeline from failing if the bam file is not valid

    for bam in \$(ls *.bam)
    do
    docker run --rm \
       --name gluetools \
        -v \$PWD:/opt/bams \
        -w /opt/bams \
        --link gluetools-mysql \
        cvrbioinformatics/gluetools:latest gluetools.sh \
         -p cmd-result-format:json \
        -EC \
        -i project hcv module phdrReportingController invoke-function reportBam \${bam} 15.0 > \${bam}.json || true
    done

    #docker stop gluetools-mysql 
    # Remove the image
    #docker rm gluetools-mysql
    

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
      \$(grep "projectVersion" *.json | awk '{print \$2}' | uniq | tr -d '"' | tr -d "," | sed 's/:/: /g')
      \$(grep "engineVersion" *.json | awk '{print \$2}' | uniq | tr -d '"' | tr -d "," | sed 's/:/: /g')
      \$(grep "extensionVersion" *.json | awk '{print \$2}' | uniq | tr -d '"' | tr -d "," | sed 's/:/: /g')
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
