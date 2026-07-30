from fastapi import Depends, Header, HTTPException, status

from app.models import Role, UserContext


def _parse_demo_token(token: str) -> UserContext:
    if token == "demo-consultant":
        return UserContext(uid="consultant-1", email="consultant@landroid.app", role="consultant")
    if token == "demo-owner":
        return UserContext(uid="owner-1", email="owner@landroid.app", role="landowner")
    if token == "demo-owner-2":
        return UserContext(uid="owner-2", email="owner2@landroid.app", role="landowner")
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")


def get_current_user(authorization: str = Header(default="")) -> UserContext:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    token = authorization.replace("Bearer ", "", 1).strip()
    return _parse_demo_token(token)


def require_role(*roles: Role):
    def dependency(user: UserContext = Depends(get_current_user)) -> UserContext:
        if user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden for this role")
        return user

    return dependency
