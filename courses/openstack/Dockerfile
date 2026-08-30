# SnackLab — OpenStack course "content" image (snacklab-openstack-course)
#
# Carries only the course bundle (course.json + modules/) under /course; the
# chart's course initContainer copies it into the portal's shared volume and the
# portal loads it via CONTENT_DIRS. (The learner *environment* image is separate
# → openstack-lab/, referenced by course.json's image field.)
#
# Build context = repository root (build.sh openstack-course [tag]).
FROM busybox:1.36
COPY courses/openstack/course.json /course/course.json
COPY courses/openstack/modules     /course/modules
# Build-time sanity: record the module count
RUN ls -1 /course/modules | wc -l > /course/.module-count
