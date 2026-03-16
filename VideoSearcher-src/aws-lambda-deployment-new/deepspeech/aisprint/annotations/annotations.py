def annotation(config):
# Dummy decorator that mimics aisprint.annotations.annotation
# In AWS Lambda, AI SPRINT is not used.
    def decorator(func):
        return func
    return decorator
