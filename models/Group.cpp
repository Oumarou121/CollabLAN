#include "Group.h"

namespace models {

Group::Group()
{
}

Group::Group(qint64 id, const QString &name)
    : m_id(id)
    , m_name(name)
{
}

} // namespace models
