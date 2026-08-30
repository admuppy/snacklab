# SnackLab — CKS practice-exam "content" image
# (snacklab-cks-course)
#
# Same contract as the k8s/cka courses: bundle course.json + modules/ under /course.
# The chart's course initContainer copies it to /courses/cks and the portal loads it via
# CONTENT_DIRS. The learner-pod environment image is shared with the k8s track
# (course.json image = snacklab-k8s).
#
# Build context = repository root (build.sh cks-course [tag]).
FROM busybox:1.36
COPY courses/cks/course.json /course/course.json
COPY courses/cks/modules     /course/modules
RUN ls -1 /course/modules | wc -l > /course/.module-count
