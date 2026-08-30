# SnackLab — CKAD practice-exam "content" image
# (snacklab-ckad-course)
#
# Same contract as the k8s course: the bundle (course.json + modules/) just lives
# in /course. The chart's course initContainer copies it to /courses/ckad and the
# portal loads it via CONTENT_DIRS. The learner environment image is shared with
# the k8s track (course.json's image = snacklab-k8s).
#
# Build context = repository root (build.sh ckad-course [tag]).
FROM busybox:1.36
COPY courses/ckad/course.json /course/course.json
COPY courses/ckad/modules     /course/modules
RUN ls -1 /course/modules | wc -l > /course/.module-count
